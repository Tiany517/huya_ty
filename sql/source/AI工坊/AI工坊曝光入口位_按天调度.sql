-- ============================================================
-- AI工坊曝光入口位拆分（按天调度版）
-- 调度变量：${tdate?string('yyyy-MM-dd')}
-- 输出表：zhgametemp.zty_ads_huya_ai_gift_exposure_slot_daily_v1
--   dt, game_id, exposure_slot, slot_type, exposure_user_cnt, click_user_cnt
-- 说明：
--   - 运营位=平台下发入口；用户主动=用户自己打开礼物面板；用户触发=生成完成弹窗
--   - exposure_slot = 'ALL_SLOTS' 的行为该品类当日去重曝光/点击用户数（不区分入口位），
--     用于计算入口占比的去重分母和"曝光/DAU"
--   - 同一用户当日可命中多个入口位，按入口位分行统计时会重复计入
-- ============================================================

create table if not exists zhgametemp.zty_ads_huya_ai_gift_exposure_slot_daily_v1 (
    game_id           string comment '游戏品类ID',
    exposure_slot     string comment '曝光入口位，ALL_SLOTS 表示该品类当日去重总量',
    slot_type         string comment '运营控制 / 用户主动路径 / 用户触发 / 全部入口位',
    exposure_user_cnt bigint comment '当日去重曝光用户数',
    click_user_cnt    bigint comment '当日去重点击用户数'
)
partitioned by (
    dt string comment '日期分区，yyyy-MM-dd'
)
stored as orc;

insert overwrite table zhgametemp.zty_ads_huya_ai_gift_exposure_slot_daily_v1
partition (dt = '${tdate?string('yyyy-MM-dd')}')

with ev as (
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
),

slot_base as (
    -- 每个曝光/点击事件落到具体入口位
    select
        game_id,
        user_ukey,
        is_click,
        case
            when eventid like '%/gift_banner'              and banner_type = '15'    then '运营位-礼物banner'
            when eventid like '%/gift_activity_banner'     and activity_id = '0'     then '运营位-礼物活动banner'
            when eventid like '%/liveactive_banner'        and banner_id   = '2931'  then '运营位-活动banner2931'
            when eventid like '%/liveroom/interactive1'    and activity_id = '35851' then '运营位-直播间互动位'
            when eventid like '%/aigift_entra'             and product in ('huya_pcexe', 'huya_web') then '运营位-PC入口'
            when eventid like '%/gift_tab'                 and tab = 'AI工坊'        then '用户主动-AI工坊tab'
            when eventid like '%/gift_tab'                 and tab = '礼物'
                 and (product in ('huya_pcexe', 'huya_web') or ver_num >= 13003090) then '用户主动-礼物tab'
            when eventid like '%/liveroom_universal_popup' and popup_id = 'aigiftfinished_usertrigger' then '用户触发-生成完成弹窗'
        end as exposure_slot
    from ev
)

select
    cast(game_id as string)              as game_id,
    coalesce(exposure_slot, 'ALL_SLOTS') as exposure_slot,
    case
        when exposure_slot is null          then '全部入口位'
        when exposure_slot like '运营位%'   then '运营控制'
        when exposure_slot like '用户主动%' then '用户主动路径'
        else '用户触发'
    end                                  as slot_type,
    count(distinct case when is_click = 0 then user_ukey end) as exposure_user_cnt,
    count(distinct case when is_click = 1 then user_ukey end) as click_user_cnt
from slot_base
group by
    cast(game_id as string),
    exposure_slot
grouping sets (
    (cast(game_id as string), exposure_slot),
    (cast(game_id as string))
);
