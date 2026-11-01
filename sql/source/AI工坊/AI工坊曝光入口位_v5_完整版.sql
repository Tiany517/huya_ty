-- ============================================================
-- AI工坊曝光入口位（v5 完整版：8 组入口全保留，不分新老）
-- 调度变量：${tdate?string('yyyy-MM-dd')}
-- 输出表：zhgametemp.zty_ads_huya_ai_gift_exposure_slot_daily_v5
--   粒度：dt × game_id × game_name × entry_name × eventid × platform
--   字段：game_id, game_name, entry_name, eventid, platform, exposure_user_cnt, click_user_cnt
--
-- 为什么 8 组都留着：
--   「礼物banner(banner_type=15)」「直播间活动位(banner_id=2931)」「直播间互动位(activity_id=35851)」
--   这几组现在已无曝光量（活动位在 9 月初前后撤掉），但 7/13-9/7 期间有数据，
--   所以一律保留、不按现网量裁剪，保证全周期口径一致。
--
-- 8 组口径（与之前整理的表一致）：
--   礼物活动banner        show/click/gift_activity_banner     activity_id = '0'
--   礼物banner            show/click/gift_banner              banner_type = '15'
--   生成完成弹窗          show/click/liveroom_universal_popup popup_id = 'aigiftfinished_usertrigger'
--   礼物面板-AI工坊        show/click/gift_tab                tab = 'AI工坊'
--   礼物面板-礼物          show/click/gift_tab                tab = '礼物' 且 版本 >= 13.0.30.90
--   直播间活动位          show/click/liveactive_banner       banner_id = '2931'
--   直播间互动位          show/click/liveroom/interactive1   activity_id = '35851'
--   PC入口               show/click/aigift_entra            product 仅 pcexe/web
--
-- platform（端口）：app = huya_andriod/huya_ios，pc = huya_pcexe，web = huya_web
-- 7 组入口不锁端口，谁在哪个端触发就落哪个 platform；只有 PC入口 按埋点定义锁 pcexe/web
--
-- 写法：不用 CTE（insert 后不能跟 with）、不用 nullif（Hive 报 Invalid function nullif）、
--       不用 grouping sets，一次扫描，Hive / Spark 都能跑
-- ============================================================

create table if not exists zhgametemp.zty_ads_huya_ai_gift_exposure_slot_daily_v5 (
    game_id           string comment '游戏品类ID',
    game_name         string comment '游戏品类名称',
    entry_name        string comment '入口组名：礼物活动banner/礼物banner/生成完成弹窗/礼物面板-AI工坊/礼物面板-礼物/直播间活动位/直播间互动位/PC入口',
    eventid           string comment '实际埋点（show/click 成对），如 show/click/gift_tab',
    platform          string comment '端口：app / pc / web',
    exposure_user_cnt bigint comment '当日去重曝光用户数（show 埋点）',
    click_user_cnt    bigint comment '当日去重点击用户数（click 埋点）'
)
partitioned by (
    dt string comment '日期分区，yyyy-MM-dd'
)
stored as orc;

insert overwrite table zhgametemp.zty_ads_huya_ai_gift_exposure_slot_daily_v5
partition (dt = '${tdate?string('yyyy-MM-dd')}')

select
    base.game_id        as game_id,
    base.game_name      as game_name,
    case base.entry_code
        when 'gift_activity_banner'  then '礼物活动banner'
        when 'gift_banner'           then '礼物banner'
        when 'aigift_finished_popup' then '生成完成弹窗'
        when 'gift_tab_ai'           then '礼物面板-AI工坊'
        when 'gift_tab_gift'         then '礼物面板-礼物'
        when 'liveactive_banner'     then '直播间活动位'
        when 'liveroom_interactive1' then '直播间互动位'
        when 'aigift_entra'          then 'PC入口'
    end as entry_name,
    case base.entry_code
        when 'gift_activity_banner'  then 'show/click/gift_activity_banner'
        when 'gift_banner'           then 'show/click/gift_banner'
        when 'aigift_finished_popup' then 'show/click/liveroom_universal_popup'
        when 'gift_tab_ai'           then 'show/click/gift_tab'
        when 'gift_tab_gift'         then 'show/click/gift_tab'
        when 'liveactive_banner'     then 'show/click/liveactive_banner'
        when 'liveroom_interactive1' then 'show/click/liveroom/interactive1'
        when 'aigift_entra'          then 'show/click/aigift_entra'
    end as eventid,
    base.platform as platform,
    count(distinct case when base.is_click = 0 then base.user_ukey end) as exposure_user_cnt,
    count(distinct case when base.is_click = 1 then base.user_ukey end) as click_user_cnt
from (
    -- 事件明细：归一 platform 和 entry_code，只保留命中 AI工坊口径的事件
    select
        cast(e.gameid as string) as game_id,
        g.game_name              as game_name,
        cast(e.ukey as string)   as user_ukey,
        case
            when e.eventid like 'click/%' then 1
            else 0
        end as is_click,
        case
            when e.product in ('huya_andriod', 'huya_ios') then 'app'
            when e.product = 'huya_pcexe'                  then 'pc'
            when e.product = 'huya_web'                    then 'web'
        end as platform,
        case
            when e.eventid like '%/gift_activity_banner'     and get_json_object(e.ext['prop'], '$.activity_id') = '0'     then 'gift_activity_banner'
            when e.eventid like '%/gift_banner'              and get_json_object(e.ext['prop'], '$.banner_type') = '15'    then 'gift_banner'
            when e.eventid like '%/liveroom_universal_popup' and get_json_object(e.ext['prop'], '$.popup_id') = 'aigiftfinished_usertrigger' then 'aigift_finished_popup'
            when e.eventid like '%/gift_tab'                 and get_json_object(e.ext['prop'], '$.tab') = 'AI工坊'       then 'gift_tab_ai'
            when e.eventid like '%/gift_tab'                 and get_json_object(e.ext['prop'], '$.tab') = '礼物'
                 and (coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 1) as bigint), 0) * 1000000
                    + coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 2) as bigint), 0) * 1000
                    + coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 3) as bigint), 0)) >= 13003090 then 'gift_tab_gift'
            when e.eventid like '%/liveactive_banner'        and get_json_object(e.ext['prop'], '$.banner_id') = '2931' then 'liveactive_banner'
            when e.eventid like '%/liveroom/interactive1'    and get_json_object(e.ext['prop'], '$.activity_id') = '35851' then 'liveroom_interactive1'
            when e.eventid like '%/aigift_entra'             and e.product in ('huya_pcexe', 'huya_web') then 'aigift_entra'
        end as entry_code
    from gamelive.dwd_huya_event e
    left join (
        select
            game_id,
            max(game_name) as game_name
        from gamelive.dim_huya_game_d_a
        where dt = '${tdate?string('yyyy-MM-dd')}'
        group by game_id
    ) g
      on e.gameid = g.game_id
    where e.dt = '${tdate?string('yyyy-MM-dd')}'
      and e.ety = 'custom_event'
      and e.product in ('huya_andriod', 'huya_ios', 'huya_pcexe', 'huya_web')
      and e.yyuid is not null
      and lower(cast(e.yyuid as string)) not in ('0', 'other')
      and e.ukey is not null
      and e.gameid is not null
      and e.gameid <> ''
      and e.eventid in (
            'show/gift_activity_banner', 'click/gift_activity_banner',
            'show/gift_banner',          'click/gift_banner',
            'show/liveroom_universal_popup', 'click/liveroom_universal_popup',
            'show/gift_tab',             'click/gift_tab',
            'show/liveactive_banner',    'click/liveactive_banner',
            'show/liveroom/interactive1', 'click/liveroom/interactive1',
            'show/aigift_entra',         'click/aigift_entra'
      )
) base
where base.entry_code is not null
group by
    base.game_id,
    base.game_name,
    base.entry_code,
    base.platform
;

