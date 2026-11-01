-- ============================================================
-- AI工坊曝光入口位 v5（按天调度）
-- 调度变量：${tdate?string('yyyy-MM-dd')}
-- 输出表：zhgametemp.zty_ads_huya_ai_gift_exposure_slot_daily_v5
-- 粒度：dt × game_id × game_name × entry_name × eventid × platform
-- 口径对齐 zty_ads_huya_ai_gift_user_detail_0901_v1：
--   前 7 组入口只取 app（huya_andriod / huya_ios），PC / Web 入口分别只取 huya_pcexe / huya_web；
--   各组 prop 条件、礼物tab 版本门槛（>=13.0.30.90）一致；
--   唯一改动是去掉 nullif（Hive 不认），cast 空串本身返回 NULL，外层 coalesce(...,0) 等价。
-- platform：app = huya_andriod/huya_ios，pc = huya_pcexe，web = huya_web。
-- 暂不纳入的端口：hmos_kiwi（鸿蒙）按当前口径先不看；huya_andriod_test / huya_ios_test 为测试包，排除。
-- 以下几组现网已无曝光量（约 9 月初撤掉），但 7/13-9/7 有数据，故保留分支：
--   礼物banner(banner_type=15)、直播间活动位(banner_id=2931)、直播间互动位(activity_id=35851)。
-- ============================================================

create table if not exists zhgametemp.zty_ads_huya_ai_gift_exposure_slot_daily_v5 (
    game_id           string comment '游戏品类ID',
    game_name         string comment '游戏品类名称',
    entry_name        string comment '入口组名：礼物活动banner/礼物banner/生成完成弹窗/礼物面板-AI工坊/礼物面板-礼物/直播间活动位/直播间互动位/PC入口/Web入口',
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
    base.game_id   as game_id,
    base.game_name as game_name,
    case base.entry_code
        when 'gift_activity_banner'  then '礼物活动banner'
        when 'gift_banner'           then '礼物banner'
        when 'aigift_finished_popup' then '生成完成弹窗'
        when 'gift_tab_ai'           then '礼物面板-AI工坊'
        when 'gift_tab_gift'         then '礼物面板-礼物'
        when 'liveactive_banner'     then '直播间活动位'
        when 'liveroom_interactive1' then '直播间互动位'
        when 'aigift_pc'             then 'PC入口'
        when 'aigift_web'            then 'Web入口'
    end as entry_name,
    case base.entry_code
        when 'gift_activity_banner'  then 'show/click/gift_activity_banner'
        when 'gift_banner'           then 'show/click/gift_banner'
        when 'aigift_finished_popup' then 'show/click/liveroom_universal_popup'
        when 'gift_tab_ai'           then 'show/click/gift_tab'
        when 'gift_tab_gift'         then 'show/click/gift_tab'
        when 'liveactive_banner'     then 'show/click/liveactive_banner'
        when 'liveroom_interactive1' then 'show/click/liveroom/interactive1'
        when 'aigift_pc'             then 'show/click/aigift_entra'
        when 'aigift_web'            then 'show/click/aigift_entra'
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
            when e.product in ('huya_andriod', 'huya_ios') and e.eventid like '%/gift_activity_banner' and get_json_object(e.ext['prop'], '$.activity_id') = '0' then 'gift_activity_banner'
            when e.product in ('huya_andriod', 'huya_ios') and e.eventid like '%/gift_banner'          and get_json_object(e.ext['prop'], '$.banner_type') = '15' then 'gift_banner'
            when e.product in ('huya_andriod', 'huya_ios') and e.eventid like '%/liveroom_universal_popup' and get_json_object(e.ext['prop'], '$.popup_id') = 'aigiftfinished_usertrigger' then 'aigift_finished_popup'
            when e.product in ('huya_andriod', 'huya_ios') and e.eventid like '%/gift_tab'             and get_json_object(e.ext['prop'], '$.tab') = 'AI工坊' then 'gift_tab_ai'
            when e.product in ('huya_andriod', 'huya_ios') and e.eventid like '%/gift_tab'             and get_json_object(e.ext['prop'], '$.tab') = '礼物'
                 and (coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 1) as bigint), 0) * 1000000
                    + coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 2) as bigint), 0) * 1000
                    + coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 3) as bigint), 0)) >= 13003090 then 'gift_tab_gift'
            when e.product in ('huya_andriod', 'huya_ios') and e.eventid like '%/liveactive_banner'    and get_json_object(e.ext['prop'], '$.banner_id') = '2931' then 'liveactive_banner'
            when e.product in ('huya_andriod', 'huya_ios') and e.eventid like '%/liveroom/interactive1' and get_json_object(e.ext['prop'], '$.activity_id') = '35851' then 'liveroom_interactive1'
            when e.product = 'huya_pcexe' and e.eventid like '%/aigift_entra' then 'aigift_pc'
            when e.product = 'huya_web'   and e.eventid like '%/aigift_entra' then 'aigift_web'
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

