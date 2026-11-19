-- 游戏品类月度核心指标：收入、观看、开播主播。
-- 引擎：Presto；时间：2026-07-01 至 2026-10-31。
-- 开播主播口径：dm_huya_ayyuid_detail_day 关联游戏维表，仅保留 game_label='游戏'。
-- live_mins 字段名虽然是 mins，但实际单位为小时；乘以 60 后判断是否达到 15 分钟有效开播。
with game_info as (
    select
        game_id,
        max(game_label) as game_label
    from gamelive.dim_huya_game_d_a
    where dt = '2026-11-18'
    group by game_id
),
consume_user_month as (
    -- 粒度：mth + user_ukey；同一用户一个月内先汇总消费，再判断是否大R。
    select
        substr(dt, 1, 7) as mth,
        cast(ext['ukey'] as varchar) as user_ukey,
        sum(cast(user_consume_amount as double)) as user_consume_amount
    from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i
    where dt between '2026-07-01' and '2026-10-31'
      and cast(user_consume_amount as double) > 0
      and coalesce(is_free_item, 0) = 0
      and ext['ukey'] is not null
      and trim(cast(ext['ukey'] as varchar)) not in ('', '0', '-1')
      and cast(game_label as varchar) in ('游戏')
    group by
        substr(dt, 1, 7),
        cast(ext['ukey'] as varchar)
),
consume_metric as (
    -- 粒度：mth；付费用户数即用户×月去重人数。
    select
        mth,
        count(*) as pay_user_cnt,
        sum(user_consume_amount) as pay_consume_amt,
        count_if(user_consume_amount >= 1000) as big_r_user_cnt,
        sum(case when user_consume_amount >= 1000 then user_consume_amount else 0 end) as big_r_consume_amt
    from consume_user_month
    group by mth
),
consume_metric_ratio as (
    select
        mth,
        pay_user_cnt,
        pay_consume_amt,
        pay_consume_amt * 1.0 / nullif(pay_user_cnt, 0) as avg_payer_consume_amt,
        big_r_user_cnt,
        big_r_consume_amt,
        big_r_consume_amt * 1.0 / nullif(big_r_user_cnt, 0) as avg_big_r_consume_amt,
        big_r_consume_amt * 1.0 / nullif(pay_consume_amt, 0) as big_r_revenue_ratio
    from consume_metric
),
watch_base as (
    -- 粒度：dt + user_ukey + creator_uid；仅游戏标签的直播观看行为。
    select
        dt,
        substr(dt, 1, 7) as mth,
        cast(user_ukey as varchar) as user_ukey,
        cast(creator_uid as varchar) as creator_uid
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2026-07-01' and '2026-10-31'
      and data_type = 'live_watch_session'
      and live_content_type = '直播'
      and creator_uid is not null
      and trim(cast(creator_uid as varchar)) <> ''
      and cast(game_label as varchar) in ('游戏')
),
watch_mau as (
    -- 粒度：mth；月活跃观看用户数和月观看主播数。
    select
        mth,
        count(distinct user_ukey) as mau,
        count(distinct creator_uid) as monthly_vist_anchor_cnt
    from watch_base
    group by mth
),
watch_day as (
    -- 粒度：dt；用于计算月内日峰值的简单平均。
    select
        dt,
        mth,
        count(distinct user_ukey) as user_cnt,
        count(distinct creator_uid) as anchor_cnt
    from watch_base
    group by
        dt,
        mth
),
watch_dau as (
    select
        mth,
        avg(user_cnt) as dau,
        avg(anchor_cnt) as daily_vist_anchor_cnt
    from watch_day
    group by mth
),
live_anchor_day as (
    -- 粒度：dt + ayyuid；开播游戏中仅保留当日直播时长大于 0 的主播。
    select
        a.dt,
        substr(a.dt, 1, 7) as mth,
        cast(a.ayyuid as varchar) as ayyuid,
        sum(coalesce(cast(a.live_mins as double), 0)) as live_hours
    from gamelive.dm_huya_ayyuid_detail_day a
    inner join game_info b
      on cast(a.gameid as varchar) = cast(b.game_id as varchar)
    where a.dt between '2026-07-01' and '2026-10-31'
      and b.game_label in ('游戏')
    group by
        a.dt,
        substr(a.dt, 1, 7),
        cast(a.ayyuid as varchar)
    having sum(coalesce(cast(a.live_mins as double), 0)) > 0
),
valid_live_anchor_day as (
    -- 粒度：dt + ayyuid；单日累计开播达到 15 分钟才算有效开播日。
    select
        dt,
        mth,
        ayyuid
    from live_anchor_day
    where live_hours * 60 >= 15
),
monthly_live_anchor as (
    select
        mth,
        count(distinct ayyuid) as monthly_live_anchor_cnt
    from live_anchor_day
    group by mth
),
daily_live_anchor as (
    select
        mth,
        avg(live_anchor_cnt) as daily_live_anchor_cnt
    from (
        select
            dt,
            mth,
            count(distinct ayyuid) as live_anchor_cnt
        from live_anchor_day
        group by
            dt,
            mth
    ) t
    group by mth
),
monthly_valid_live_anchor as (
    select
        mth,
        count(distinct ayyuid) as monthly_valid_live_anchor_cnt
    from valid_live_anchor_day
    group by mth
),
daily_valid_live_anchor as (
    select
        mth,
        avg(live_anchor_cnt) as daily_valid_live_anchor_cnt
    from (
        select
            dt,
            mth,
            count(distinct ayyuid) as live_anchor_cnt
        from valid_live_anchor_day
        group by
            dt,
            mth
    ) t
    group by mth
),
month_base as (
    select distinct mth
    from watch_mau
)
select
    m.mth as "月份",
    coalesce(c.pay_user_cnt, 0) as "付费用户数",
    round(c.avg_payer_consume_amt, 2) as "付费用户人均消费金额",
    coalesce(c.big_r_user_cnt, 0) as "大R用户数",
    round(c.big_r_consume_amt, 2) as "大R用户消费金额",
    round(c.avg_big_r_consume_amt, 2) as "大R用户人均消费金额",
    round(c.big_r_revenue_ratio, 6) as "大R消费金额占比",
    coalesce(wm.mau, 0) as "月活跃观看用户数_MAU",
    coalesce(wm.monthly_vist_anchor_cnt, 0) as "月观看主播数",
    round(wd.dau, 2) as "日均观看用户数_DAU",
    round(wd.daily_vist_anchor_cnt, 2) as "日均观看主播数",
    coalesce(ml.monthly_live_anchor_cnt, 0) as "月开播主播数",
    round(dl.daily_live_anchor_cnt, 2) as "日均开播主播数",
    coalesce(mv.monthly_valid_live_anchor_cnt, 0) as "月有效开播主播数_15分钟",
    round(dv.daily_valid_live_anchor_cnt, 2) as "日均有效开播主播数"
from month_base m
left join consume_metric_ratio c
  on m.mth = c.mth
left join watch_mau wm
  on m.mth = wm.mth
left join watch_dau wd
  on m.mth = wd.mth
left join monthly_live_anchor ml
  on m.mth = ml.mth
left join daily_live_anchor dl
  on m.mth = dl.mth
left join monthly_valid_live_anchor mv
  on m.mth = mv.mth
left join daily_valid_live_anchor dv
  on m.mth = dv.mth
order by m.mth
