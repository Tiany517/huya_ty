-- ============================================================
-- AI工坊曝光入口位拆分（按天调度版 v4，Hive 语法）
-- 调度变量：${tdate?string('yyyy-MM-dd')}
-- 输出表：zhgametemp.zty_ads_huya_ai_gift_exposure_slot_daily_v2
--   字段：game_id, entry_icon, exposure_slot, slot_type, exposure_user_cnt, click_user_cnt
--
-- 相对 v2/v3 的改动（口径不变，只改写法以适配 Hive）：
--   1) insert 后面不能直接跟 with：CTE 全部改成内联子查询；
--   2) Hive 不支持 nullif（报 Invalid function nullif）：去掉 nullif，直接
--      cast(regexp_extract(...) as bigint)，取不到值时 Hive 返回 NULL，外层再 coalesce(..., 0)；
--   3) Hive 的 grouping sets 对 select 列表有额外限制，且 count(distinct) 与 grouping sets
--      组合在不同版本表现不一致：改成三段 union all，分别输出「入口位明细 / 图标合计 / 全部入口位」，
--      不再使用 grouping() 函数；
--   4) 只保留命中 AI工坊口径的事件（tab 不是礼物/AI工坊、版本低于门槛、banner/activity 不匹配的事件
--      不计入任何一行）。
--
-- 口径说明：
--   - slot_type：运营控制 / 用户主动路径 / 用户触发 / 图标合计 / 全部入口位
--   - entry_icon（入口图标来源）：
--       礼物icon     = gift_banner(banner_type=15)
--                      gift_activity_banner(activity_id=0)
--                      gift_tab(tab=礼物，版本>=13.0.30.90)
--       AI工坊icon   = gift_tab(tab=AI工坊)
--                      aigift_entra(PC端AI礼物入口)
--                      liveroom_universal_popup(popup_id=aigiftfinished_usertrigger)
--       直播间活动位 = liveactive_banner(banner_id=2931)
--                      liveroom/interactive1(activity_id=35851)
--       注：直播间活动位 = 直播间右上角的活动位/互动位，与「右下角礼物图标→礼物面板→AI工坊」
--           是两个不同入口；该位置只在 AI工坊上线初期投放，曝光量天然带时间窗，需按投放期单独看。
--   - 合计行：
--       entry_icon='ALL_ICONS' + exposure_slot='ALL_SLOTS' = 该品类当日去重曝光/点击用户数（全部入口位）
--       entry_icon=<具体图标>  + exposure_slot='ALL_SLOTS' = 该图标下各入口位合计
--   - 去重口径：同一天同一用户命中多个入口位时，按入口位分行会重复计入；合计行才是去重后的用户数。
--   - 入口位命名与 ai_exposure_slot_report.py 的 SLOT_ORDER 一致（大小写敏感）。
--   - 三段 union all 会各扫一遍当天分区，单天调度可接受；如需省资源可再改成落中间表。
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

-- 1) 入口位明细：每个 entry_icon × exposure_slot 一行
select
    base.game_id as game_id,
    base.entry_icon as entry_icon,
    base.exposure_slot as exposure_slot,
    case
        when base.exposure_slot like '运营位%' then '运营控制'
        when base.exposure_slot like '用户主动%' then '用户主动路径'
        else '用户触发'
    end as slot_type,
    count(distinct case when base.is_click = 0 then base.user_ukey end) as exposure_user_cnt,
    count(distinct case when base.is_click = 1 then base.user_ukey end) as click_user_cnt
from (
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
        -- 事件明细：限定日期分区、端、事件名单，并把 prop 里的入口参数解析出来
        select
            cast(e.gameid as string) as game_id,
            cast(e.ukey as string) as user_ukey,
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
            -- 客户端版本号：13.0.30.90 -> 13003090，用于还原礼物tab曝光的版本门槛
            coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 1) as bigint), 0) * 1000000
          + coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 2) as bigint), 0) * 1000
          + coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 3) as bigint), 0) as ver_num
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
) base
where base.exposure_slot is not null
group by
    base.game_id,
    base.entry_icon,
    base.exposure_slot

union all

-- 2) 图标合计：该图标下各入口位去重合计
select
    base.game_id as game_id,
    base.entry_icon as entry_icon,
    'ALL_SLOTS' as exposure_slot,
    '图标合计' as slot_type,
    count(distinct case when base.is_click = 0 then base.user_ukey end) as exposure_user_cnt,
    count(distinct case when base.is_click = 1 then base.user_ukey end) as click_user_cnt
from (
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
        -- 事件明细：限定日期分区、端、事件名单，并把 prop 里的入口参数解析出来
        select
            cast(e.gameid as string) as game_id,
            cast(e.ukey as string) as user_ukey,
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
            -- 客户端版本号：13.0.30.90 -> 13003090，用于还原礼物tab曝光的版本门槛
            coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 1) as bigint), 0) * 1000000
          + coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 2) as bigint), 0) * 1000
          + coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 3) as bigint), 0) as ver_num
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
) base
where base.exposure_slot is not null
group by
    base.game_id,
    base.entry_icon

union all

-- 3) 全部入口位：该品类当日去重曝光/点击用户数
select
    base.game_id as game_id,
    'ALL_ICONS' as entry_icon,
    'ALL_SLOTS' as exposure_slot,
    '全部入口位' as slot_type,
    count(distinct case when base.is_click = 0 then base.user_ukey end) as exposure_user_cnt,
    count(distinct case when base.is_click = 1 then base.user_ukey end) as click_user_cnt
from (
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
        -- 事件明细：限定日期分区、端、事件名单，并把 prop 里的入口参数解析出来
        select
            cast(e.gameid as string) as game_id,
            cast(e.ukey as string) as user_ukey,
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
            -- 客户端版本号：13.0.30.90 -> 13003090，用于还原礼物tab曝光的版本门槛
            coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 1) as bigint), 0) * 1000000
          + coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 2) as bigint), 0) * 1000
          + coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 3) as bigint), 0) as ver_num
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
) base
where base.exposure_slot is not null
group by
    base.game_id
;

