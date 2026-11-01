-- ============================================================
-- AI工坊曝光入口位拆分（按天调度版 v3，修复语法报错）
-- 调度变量：${tdate?string('yyyy-MM-dd')}
-- 输出表：zhgametemp.zty_ads_huya_ai_gift_exposure_slot_daily_v2（表名与 v2 一致，下游不用改）
--   dt, game_id, entry_icon, exposure_slot, slot_type, exposure_user_cnt, click_user_cnt
--
-- v3 相对 v2 的改动（只改语法，不改口径）：
--   1) 去掉紧跟在 insert 后面的 with ... as：INSERT 子句后面只接受 SELECT，
--      原来的 CTE 全部改写为内联子查询（ev -> 最内层子查询，slot_base -> 外层子查询 s）；
--   2) 去掉 "group by a,b,c grouping sets(...)" 的写法：两者同时出现会把明细行多算一遍，
--      改成只写 group by grouping sets(...)；
--   3) 合计行标签改用 grouping() 判断，避免和真实为空的入口位混淆；
--   4) 增加 where exposure_slot is not null：只保留命中 AI工坊口径的事件（tab 非礼物/AI工坊、
--      版本低于门槛、banner 不是 2931 等未命中事件不计入任何一行）。
--
-- 说明：
--   - slot_type：运营控制 / 用户主动路径 / 用户触发 / 图标合计 / 全部入口位
--   - entry_icon 区分入口图标来源：
--       礼物icon   = gift_banner(banner_type=15)
--                    gift_activity_banner(activity_id=0)
--                    gift_tab(tab=礼物，版本>=13.0.30.90)
--       AI工坊icon = gift_tab(tab=AI工坊)
--                    aigift_entra(PC端AI礼物入口)
--                    liveroom_universal_popup(popup_id=aigiftfinished_usertrigger)
--       直播间活动位 = liveactive_banner(banner_id=2931)
--                      liveroom/interactive1(activity_id=35851)
--       注：直播间活动位 = 直播间右上角的活动位/互动位，与"右下角礼物图标进礼物面板再找AI工坊"
--           是两个不同入口；该位置仅在 AI工坊上线初期有一段时间专门用于AI工坊曝光，
--           因此它的曝光量天然带时间窗，分析需按投放期单独看，不能直接和全周期其他入口混算
--   - 合计行：
--       entry_icon='ALL_ICONS' + exposure_slot='ALL_SLOTS' = 该品类当日去重曝光/点击总量
--       entry_icon=<具体图标>  + exposure_slot='ALL_SLOTS' = 该图标下各入口位合计
--   - 用户口径：同一用户当日可命中多个入口位，按入口位分行统计时会重复计入
--   - 入口位命名与 ai_exposure_slot_report.py 的 SLOT_ORDER 保持一致（大小写敏感）
-- ============================================================

create table if not exists zhgametemp.zty_ads_huya_ai_gift_exposure_slot_daily_v2 (
    game_id           string comment '游戏品类ID',
    entry_icon        string comment '入口图标：礼物icon / AI工坊icon / 直播间活动位，ALL_ICONS 表示全部',
    exposure_slot     string comment '曝光入口位，ALL_SLOTS 表示该图标/该品类当日去重总量',
    slot_type         string comment '运营控制 / 用户主动路径 / 用户触发 / 图标合计 / 全部入口位',
    exposure_user_cnt bigint comment '当日去重曝光用户数',
    click_user_cnt    bigint comment '当日去重点击用户数'
)
partitioned by (
    dt string comment '日期分区，yyyy-MM-dd'
)
stored as orc;

insert overwrite table zhgametemp.zty_ads_huya_ai_gift_exposure_slot_daily_v2
partition (dt = '${tdate?string('yyyy-MM-dd')}')

select
    cast(s.game_id as string) as game_id,
    case when grouping(s.entry_icon) = 1 then 'ALL_ICONS' else s.entry_icon end as entry_icon,
    case when grouping(s.exposure_slot) = 1 then 'ALL_SLOTS' else s.exposure_slot end as exposure_slot,
    case
        when grouping(s.exposure_slot) = 1 and grouping(s.entry_icon) = 1 then '全部入口位'
        when grouping(s.exposure_slot) = 1 then '图标合计'
        when s.exposure_slot like '运营位%' then '运营控制'
        when s.exposure_slot like '用户主动%' then '用户主动路径'
        else '用户触发'
    end as slot_type,
    count(distinct case when s.is_click = 0 then s.user_ukey end) as exposure_user_cnt,
    count(distinct case when s.is_click = 1 then s.user_ukey end) as click_user_cnt
from (
    -- 每个曝光/点击事件同时落到入口图标和具体入口位
    select
        ev.game_id,
        ev.user_ukey,
        ev.is_click,
        case
            when ev.eventid like '%/gift_banner'              and ev.banner_type = '15'    then '运营位-礼物banner'
            when ev.eventid like '%/gift_activity_banner'     and ev.activity_id = '0'     then '运营位-礼物活动banner'
            when ev.eventid like '%/liveactive_banner'        and ev.banner_id   = '2931'  then '运营位-活动banner2931'
            when ev.eventid like '%/liveroom/interactive1'    and ev.activity_id = '35851' then '运营位-直播间互动位'
            when ev.eventid like '%/aigift_entra'             and ev.product in ('huya_pcexe', 'huya_web') then '运营位-PC入口'
            when ev.eventid like '%/gift_tab'                 and ev.tab = 'AI工坊'        then '用户主动-AI工坊tab'
            when ev.eventid like '%/gift_tab'                 and ev.tab = '礼物'
                 and (ev.product in ('huya_pcexe', 'huya_web') or ev.ver_num >= 13003090) then '用户主动-礼物tab'
            when ev.eventid like '%/liveroom_universal_popup' and ev.popup_id = 'aigiftfinished_usertrigger' then '用户触发-生成完成弹窗'
        end as exposure_slot,
        case
            when ev.eventid like '%/gift_banner'              and ev.banner_type = '15'    then '礼物icon'
            when ev.eventid like '%/gift_activity_banner'     and ev.activity_id = '0'     then '礼物icon'
            when ev.eventid like '%/gift_tab'                 and ev.tab = '礼物'
                 and (ev.product in ('huya_pcexe', 'huya_web') or ev.ver_num >= 13003090) then '礼物icon'
            when ev.eventid like '%/gift_tab'                 and ev.tab = 'AI工坊'        then 'AI工坊icon'
            when ev.eventid like '%/aigift_entra'             and ev.product in ('huya_pcexe', 'huya_web') then 'AI工坊icon'
            when ev.eventid like '%/liveroom_universal_popup' and ev.popup_id = 'aigiftfinished_usertrigger' then 'AI工坊icon'
            when ev.eventid like '%/liveactive_banner'        and ev.banner_id   = '2931'  then '直播间活动位'
            when ev.eventid like '%/liveroom/interactive1'    and ev.activity_id = '35851' then '直播间活动位'
        end as entry_icon
    from (
        -- AI工坊相关 show/click 事件明细；限定 AI工坊投放的端与事件口径
        select
            e.gameid as game_id,
            e.ukey as user_ukey,
            case
                when e.eventid like 'click/%' then 1
                else 0
            end as is_click,
            e.eventid,
            e.product,
            get_json_object(e.ext['prop'], '$.banner_type') as banner_type,
            get_json_object(e.ext['prop'], '$.activity_id') as activity_id,
            get_json_object(e.ext['prop'], '$.banner_id')   as banner_id,
            get_json_object(e.ext['prop'], '$.popup_id')    as popup_id,
            get_json_object(e.ext['prop'], '$.tab')         as tab,
            -- 客户端版本号，用于还原礼物tab曝光的版本门槛
            coalesce(cast(nullif(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 1), '') as bigint), 0) * 1000000
          + coalesce(cast(nullif(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 2), '') as bigint), 0) * 1000
          + coalesce(cast(nullif(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 3), '') as bigint), 0) as ver_num
        from gamelive.dwd_huya_event e
        where e.dt = '${tdate?string('yyyy-MM-dd')}'
          and e.ety = 'custom_event'
          and e.product in ('huya_andriod', 'huya_ios', 'huya_pcexe', 'huya_web')
          and e.yyuid is not null
          and lower(cast(e.yyuid as string)) not in ('0', 'other')
          and e.ukey is not null
          and e.gameid is not null
          and e.gameid <> ''
          and e.eventid in (
                'show/gift_banner',              'click/gift_banner',
                'show/gift_activity_banner',     'click/gift_activity_banner',
                'show/liveactive_banner',        'click/liveactive_banner',
                'show/liveroom/interactive1',    'click/liveroom/interactive1',
                'show/liveroom_universal_popup', 'click/liveroom_universal_popup',
                'show/gift_tab',                 'click/gift_tab',
                'show/aigift_entra',             'click/aigift_entra'
          )
    ) ev
) s
where s.exposure_slot is not null
group by grouping sets (
    (s.game_id, s.entry_icon, s.exposure_slot),
    (s.game_id, s.entry_icon),
    (s.game_id)
);

