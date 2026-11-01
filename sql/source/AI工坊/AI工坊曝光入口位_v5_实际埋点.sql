-- ============================================================
-- AI工坊曝光入口位（v5：只保留一列实际埋点，去掉 entry_icon / exposure_slot / slot_type）
-- 调度变量：${tdate?string('yyyy-MM-dd')}
-- 输出表：zhgametemp.zty_ads_huya_ai_gift_exposure_slot_daily_v5
--   字段：game_id, exposure_event, exposure_user_cnt, click_user_cnt
--
-- exposure_event 取值（就是实际埋点 eventid，需要 prop 才能区分的拼上关键 prop）：
--   gift_banner@banner_type=15                                  show/click + prop.banner_type=15
--   gift_activity_banner@activity_id=0                          show/click + prop.activity_id=0
--   liveactive_banner@banner_id=2931                            show/click + prop.banner_id=2931（现网已无曝光量）
--   liveroom/interactive1@activity_id=35851                     show/click + prop.activity_id=35851（现网只有 click）
--   aigift_entra                                                show/click + product in (pcexe,web)，仅 PC
--   gift_tab@tab=AI工坊                                          show/click + prop.tab='AI工坊'，AI工坊没有独立埋点，只能靠这个 tab 认
--   gift_tab@tab=礼物                                            show/click + prop.tab='礼物' 且 版本>=13.0.30.90
--   liveroom_universal_popup@popup_id=aigiftfinished_usertrigger  show/click + prop.popup_id
--   ALL_EVENTS                                                  该品类当日全部 AI工坊入口埋点去重合计
--
-- 口径：
--   - 只保留命中 AI工坊口径的事件（tab 非礼物/AI工坊、版本低于门槛、banner/activity/popup 不匹配的不计入）
--   - 同一用户当日命中多个埋点时，按埋点分行会重复计入；ALL_EVENTS 行才是去重后的用户数
--   - 不用 CTE（insert 后面不能跟 with）、不用 nullif、不用 grouping sets，Hive / Spark 都能跑
--   - 三段扫描已压到两段（明细 + 合计）；如要加埋点，在 where 的 eventid 名单和上面 case 里各加一条即可
-- ============================================================

create table if not exists zhgametemp.zty_ads_huya_ai_gift_exposure_slot_daily_v5 (
    game_id           string comment '游戏品类ID',
    exposure_event    string comment '实际埋点：eventid[@关键prop]，如 gift_tab@tab=AI工坊 / aigift_entra / ALL_EVENTS',
    exposure_user_cnt bigint comment '当日去重曝光用户数（show 埋点）',
    click_user_cnt    bigint comment '当日去重点击用户数（click 埋点）'
)
partitioned by (
    dt string comment '日期分区，yyyy-MM-dd'
)
stored as orc;

insert overwrite table zhgametemp.zty_ads_huya_ai_gift_exposure_slot_daily_v5
partition (dt = '${tdate?string('yyyy-MM-dd')}')

-- 1) 按实际埋点明细
select
    base.game_id        as game_id,
    base.exposure_event as exposure_event,
    count(distinct case when base.is_click = 0 then base.user_ukey end) as exposure_user_cnt,
    count(distinct case when base.is_click = 1 then base.user_ukey end) as click_user_cnt
from (
    select
        cast(e.gameid as string) as game_id,
        cast(e.ukey as string)   as user_ukey,
        case
            when e.eventid like 'click/%' then 1
            else 0
        end as is_click,
        case
            when e.eventid like '%/gift_banner'              and get_json_object(e.ext['prop'], '$.banner_type') = '15'    then 'gift_banner@banner_type=15'
            when e.eventid like '%/gift_activity_banner'     and get_json_object(e.ext['prop'], '$.activity_id') = '0'     then 'gift_activity_banner@activity_id=0'
            when e.eventid like '%/liveactive_banner'        and get_json_object(e.ext['prop'], '$.banner_id')   = '2931'  then 'liveactive_banner@banner_id=2931'
            when e.eventid like '%/liveroom/interactive1'    and get_json_object(e.ext['prop'], '$.activity_id') = '35851' then 'liveroom/interactive1@activity_id=35851'
            when e.eventid like '%/aigift_entra'             and e.product in ('huya_pcexe', 'huya_web')                then 'aigift_entra'
            when e.eventid like '%/gift_tab'                 and get_json_object(e.ext['prop'], '$.tab') = 'AI工坊'       then 'gift_tab@tab=AI工坊'
            when e.eventid like '%/gift_tab'                 and get_json_object(e.ext['prop'], '$.tab') = '礼物'
                 and (e.product in ('huya_pcexe', 'huya_web')
                      or coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 1) as bigint), 0) * 1000000
                       + coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 2) as bigint), 0) * 1000
                       + coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 3) as bigint), 0) >= 13003090) then 'gift_tab@tab=礼物'
            when e.eventid like '%/liveroom_universal_popup' and get_json_object(e.ext['prop'], '$.popup_id') = 'aigiftfinished_usertrigger' then 'liveroom_universal_popup@popup_id=aigiftfinished_usertrigger'
        end as exposure_event
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
) base
where base.exposure_event is not null
group by
    base.game_id,
    base.exposure_event

union all

-- 2) 该品类当日全部 AI工坊入口埋点去重合计
select
    base.game_id  as game_id,
    'ALL_EVENTS'  as exposure_event,
    count(distinct case when base.is_click = 0 then base.user_ukey end) as exposure_user_cnt,
    count(distinct case when base.is_click = 1 then base.user_ukey end) as click_user_cnt
from (
    select
        cast(e.gameid as string) as game_id,
        cast(e.ukey as string)   as user_ukey,
        case
            when e.eventid like 'click/%' then 1
            else 0
        end as is_click,
        case
            when e.eventid like '%/gift_banner'              and get_json_object(e.ext['prop'], '$.banner_type') = '15'    then 'gift_banner@banner_type=15'
            when e.eventid like '%/gift_activity_banner'     and get_json_object(e.ext['prop'], '$.activity_id') = '0'     then 'gift_activity_banner@activity_id=0'
            when e.eventid like '%/liveactive_banner'        and get_json_object(e.ext['prop'], '$.banner_id')   = '2931'  then 'liveactive_banner@banner_id=2931'
            when e.eventid like '%/liveroom/interactive1'    and get_json_object(e.ext['prop'], '$.activity_id') = '35851' then 'liveroom/interactive1@activity_id=35851'
            when e.eventid like '%/aigift_entra'             and e.product in ('huya_pcexe', 'huya_web')                then 'aigift_entra'
            when e.eventid like '%/gift_tab'                 and get_json_object(e.ext['prop'], '$.tab') = 'AI工坊'       then 'gift_tab@tab=AI工坊'
            when e.eventid like '%/gift_tab'                 and get_json_object(e.ext['prop'], '$.tab') = '礼物'
                 and (e.product in ('huya_pcexe', 'huya_web')
                      or coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 1) as bigint), 0) * 1000000
                       + coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 2) as bigint), 0) * 1000
                       + coalesce(cast(regexp_extract(e.iver, '^(\\d+)\\.(\\d+)\\.(\\d+)', 3) as bigint), 0) >= 13003090) then 'gift_tab@tab=礼物'
            when e.eventid like '%/liveroom_universal_popup' and get_json_object(e.ext['prop'], '$.popup_id') = 'aigiftfinished_usertrigger' then 'liveroom_universal_popup@popup_id=aigiftfinished_usertrigger'
        end as exposure_event
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
) base
where base.exposure_event is not null
group by
    base.game_id
;

