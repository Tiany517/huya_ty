-- 无畏契约（5937）站内、站外主播融合后，计算 P50/P75 目标增长观时
-- 执行引擎：Presto
-- 时间范围：2026-01-01 至 2026-10-22
-- 输出：每个最终保留主播一行，同时给出 P50/P75 目标、目标增长直播时长和目标增长观时
-- 注意：站内与站外先融合到同一主播池，再做 ACU 分层、有效月门槛、赛事/俱乐部剔除、高值剔除和 60 分钟门槛；
--       P50/P75 使用融合后的头部、腰部主播池分别计算，不使用站内或站外各自的独立分位数。

with internal_anchor_day as (
    -- 站内：先聚合到主播×日，ACU 按用户确认口径取日均 ACU
    select
        cast(dt as varchar) as dt,
        cast(ayyuid as varchar) as anchor_id,
        max(
            substr(
                regexp_replace(
                    coalesce(cast(nickname as varchar), ''),
                    '[\",\r\n\t]+',
                    ' '
                ),
                1,
                100
            )
        ) as nickname,
        coalesce(avg(acu), 0) as day_acu,
        coalesce(sum(live_hours_only_live), 0) * 60.0 as day_live_minutes
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-01-01' and '2026-10-22'
      and cast(gameid as varchar) = '5937'
      and live_hours_only_live > 0
    group by
        cast(dt as varchar),
        cast(ayyuid as varchar)
),

internal_anchor as (
    -- 站内：主播年度指标；有效月份为实际有 5937 开播记录的月份，未开播月份不进入分母
    select
        '站内' as scope,
        'huya' as platform,
        anchor_id,
        max(nickname) as nickname,
        count(distinct dt) as live_day_cnt,
        count(distinct substr(dt, 1, 7)) as active_month_cnt,
        count(distinct dt) * 1.0
            / nullif(count(distinct substr(dt, 1, 7)), 0) as avg_monthly_live_days,
        coalesce(avg(day_acu), 0) as avg_daily_acu,
        coalesce(avg(day_live_minutes), 0) as avg_daily_live_minutes
    from internal_anchor_day
    group by anchor_id
),

huxiao_anchor_day as (
    -- 站外虎啸：platform='douyin' 与 douyin-huxiao 统一归入 douyin-huxiao
    select
        cast(dt as varchar) as dt,
        'douyin-huxiao' as platform,
        cast(platform_id as varchar) as anchor_id,
        max(cast(nickname as varchar)) as nickname,
        max(cast(valid_acu as double)) as day_acu,
        max(cast(live_hours as double)) * 60.0 as day_live_minutes
    from zhgametemp.zhubo_shengtai_platform_pinlei_dau_v4
    where dt between '2026-01-01' and '2026-10-22'
      and platform in ('douyin', 'douyin-huxiao')
      and pinlei = '无畏契约'
    group by
        cast(dt as varchar),
        cast(platform_id as varchar)
),

hushi_anchor_day as (
    -- 站外虎视：沿用既定换算，有效 ACU=acu/4.6，开播时长=validliveduration×60
    select
        cast(date as varchar) as dt,
        'douyin-hushi' as platform,
        cast(aweme_display_id as varchar) as anchor_id,
        max(cast(nick_name as varchar)) as nickname,
        max(cast(acu as double)) / 4.6 as day_acu,
        max(cast(validliveduration as double)) * 60.0 as day_live_minutes
    from gamelive.ads_spider_douyin_mcn_hushi_info_d_i
    where dt between '2026-01-01' and '2026-10-22'
      and date between '2026-01-01' and '2026-10-22'
      and cast(acu as double) > 0
      and game_name = '无畏契约'
    group by
        cast(date as varchar),
        cast(aweme_display_id as varchar)
),

external_anchor as (
    -- 站外：主播年度指标，口径与站内完全一致
    select
        '站外' as scope,
        platform,
        anchor_id,
        max(nickname) as nickname,
        count(distinct dt) as live_day_cnt,
        count(distinct substr(dt, 1, 7)) as active_month_cnt,
        count(distinct dt) * 1.0
            / nullif(count(distinct substr(dt, 1, 7)), 0) as avg_monthly_live_days,
        coalesce(avg(day_acu), 0) as avg_daily_acu,
        coalesce(avg(day_live_minutes), 0) as avg_daily_live_minutes
    from (
        select * from huxiao_anchor_day
        union all
        select * from hushi_anchor_day
    ) anchor_day
    group by platform, anchor_id
),

anchor_all as (
    -- 站内、站外先融合成同一主播池；平台账号分别保留，不跨平台合并同一人的多个账号
    select * from internal_anchor
    union all
    select * from external_anchor
),

head_waist as (
    -- ACU 分层：头部 >=2000；腰部 100~2000；尾部剔除
    select
        *,
        case
            when avg_daily_acu >= 2000 then '头部主播'
            when avg_daily_acu >= 100 then '腰部主播'
            else '尾部主播'
        end as acu_type
    from anchor_all
),

eligible as (
    -- 融合池统一清洗：有效月门槛、赛事/内容账号、俱乐部账号
    select *
    from head_waist
    where acu_type in ('头部主播', '腰部主播')
      and avg_monthly_live_days >= 10
      and not regexp_like(
            nickname,
            '夏季赛|春季赛|秋季赛|冬季赛|赛事|联赛|总决赛|决赛|半决赛|淘汰赛|小组赛|回顾|轮播|邀请赛|职业赛|职业联赛|公开赛|锦标赛|先锋赛|冠军赛|大师赛|季后赛|季前赛|世界赛|世俱杯|VCT|电竞|争霸赛|挑战赛|积分赛|升降级赛|全明星|精彩集锦|集锦|高光|录播|官方|主舞台|副舞台|二路|直播回放|我是一颗小虎牙|虎牙用户|小虎牙'
          )
      and not regexp_like(
            nickname,
            '^(EDG|BLG|JDG|WBG|LNG|TES|RNG|FPX|TYLOO|PeRo|NOVA|Wolves|TEC|DRG|XLG|ASE|TTG|KSG)([^A-Za-z]|$)'
          )
      and not regexp_like(
            nickname,
            '(^|[^A-Za-z0-9])(OMG|LGD|IG|WE|RA|TE|4AM)([^A-Za-z0-9]|$)'
          )
      and not regexp_like(
            nickname,
            '电子竞技俱乐部|电竞俱乐部|俱乐部|战队|青训|二队'
          )
),

duration_array as (
    select array_sort(array_agg(avg_daily_live_minutes)) as vals
    from eligible
),

outlier_stats as (
    -- 高值阈值：融合池 Q3 + 3×IQR，分位数使用线性插值
    select
        p25 as q1,
        p75 as q3,
        p75 - p25 as iqr,
        p75 + 3 * (p75 - p25) as upper_threshold
    from (
        select
            element_at(vals, cast(floor((cardinality(vals) - 1) * 0.25) as bigint) + 1)
                + (
                    element_at(vals, least(cast(floor((cardinality(vals) - 1) * 0.25) as bigint) + 2, cardinality(vals)))
                    - element_at(vals, cast(floor((cardinality(vals) - 1) * 0.25) as bigint) + 1)
                  ) * ((cardinality(vals) - 1) * 0.25 - floor((cardinality(vals) - 1) * 0.25)) as p25,
            element_at(vals, cast(floor((cardinality(vals) - 1) * 0.75) as bigint) + 1)
                + (
                    element_at(vals, least(cast(floor((cardinality(vals) - 1) * 0.75) as bigint) + 2, cardinality(vals)))
                    - element_at(vals, cast(floor((cardinality(vals) - 1) * 0.75) as bigint) + 1)
                  ) * ((cardinality(vals) - 1) * 0.75 - floor((cardinality(vals) - 1) * 0.75)) as p75
        from duration_array
    ) p
),

final_pool as (
    -- 剔除高异常后，再要求年日均开播时长不少于 60 分钟
    select e.*
    from eligible e
    cross join outlier_stats q
    where e.avg_daily_live_minutes <= q.upper_threshold
      and e.avg_daily_live_minutes >= 60
),

layer_array as (
    select
        acu_type,
        array_sort(array_agg(avg_daily_live_minutes)) as vals
    from final_pool
    group by acu_type
),

layer_target as (
    -- 头部、腰部各自使用融合池计算 P50/P75
    select
        acu_type,
        element_at(vals, cast(floor((cardinality(vals) - 1) * 0.50) as bigint) + 1)
            + (
                element_at(vals, least(cast(floor((cardinality(vals) - 1) * 0.50) as bigint) + 2, cardinality(vals)))
                - element_at(vals, cast(floor((cardinality(vals) - 1) * 0.50) as bigint) + 1)
              ) * ((cardinality(vals) - 1) * 0.50 - floor((cardinality(vals) - 1) * 0.50)) as p50_target_live_minutes,
        element_at(vals, cast(floor((cardinality(vals) - 1) * 0.75) as bigint) + 1)
            + (
                element_at(vals, least(cast(floor((cardinality(vals) - 1) * 0.75) as bigint) + 2, cardinality(vals)))
                - element_at(vals, cast(floor((cardinality(vals) - 1) * 0.75) as bigint) + 1)
              ) * ((cardinality(vals) - 1) * 0.75 - floor((cardinality(vals) - 1) * 0.75)) as p75_target_live_minutes
    from layer_array
)

select
    f.scope as "来源",
    f.platform as "平台",
    f.anchor_id as "主播ID",
    f.nickname as "主播昵称",
    f.acu_type as "ACU层级",
    round(f.avg_daily_acu, 4) as "年日均ACU",
    f.live_day_cnt as "实际开播天数",
    f.active_month_cnt as "有效月份数",
    round(f.avg_monthly_live_days, 4) as "月日均开播天数",
    round(f.avg_daily_live_minutes, 4) as "年日均开播时长_分钟",
    round(t.p50_target_live_minutes, 4) as "P50目标日均直播时长_分钟",
    round(greatest(0, t.p50_target_live_minutes - f.avg_daily_live_minutes), 4) as "P50目标增长直播时长_分钟",
    round(f.avg_daily_acu * greatest(0, t.p50_target_live_minutes - f.avg_daily_live_minutes), 4) as "P50目标增长观时_人分钟",
    round(t.p75_target_live_minutes, 4) as "P75目标日均直播时长_分钟",
    round(greatest(0, t.p75_target_live_minutes - f.avg_daily_live_minutes), 4) as "P75目标增长直播时长_分钟",
    round(f.avg_daily_acu * greatest(0, t.p75_target_live_minutes - f.avg_daily_live_minutes), 4) as "P75目标增长观时_人分钟"
from final_pool f
inner join layer_target t
    on f.acu_type = t.acu_type
order by
    case when f.acu_type = '头部主播' then 1 else 2 end,
    f.scope,
    f.avg_daily_acu desc;
