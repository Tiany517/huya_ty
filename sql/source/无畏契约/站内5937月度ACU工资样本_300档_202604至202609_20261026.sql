-- 目的：查询无畏契约（gameid=5937）站内主播的月度有效日日均 ACU 与当月工资。
-- 用途：按主播月份样本重新构建更细的 ACU 薪资参考层。
-- 时间：2026-04-01 至 2026-09-30。
-- 说明：曾尝试扩展到 2025-10，但 bp.md_dwd_anchor_salary 当前仅有 2026-04 至 2026-09 数据。
-- 工资：限定 game_name='无畏契约'、role='主播'；同主播同月多条 final_amount 先汇总，仅保留工资大于 0 的月份。
-- ACU：live_mins 单位小时，月内有效开播日需满足合计直播分钟数 >= 15；月 ACU 为有效日 ACU 简单平均。

with salary_monthly as (
  select
    substr(cast(settlement_date as varchar), 1, 7) as mth,
    cast(uid as varchar) as luid,
    max(cast(anchor_nickname as varchar)) as anchor_nickname,
    sum(coalesce(final_amount, cast(0 as decimal(18,2)))) as salary_amount
  from bp.md_dwd_anchor_salary
  where settlement_date >= '2026-04-01'
    and settlement_date < '2026-10-01'
    and cast(game_name as varchar) = '无畏契约'
    and cast(role as varchar) = '主播'
  group by
    substr(cast(settlement_date as varchar), 1, 7),
    cast(uid as varchar)
  having sum(coalesce(final_amount, cast(0 as decimal(18,2)))) > 0
),

anchor_day as (
  -- 仅扫描有正工资的站内主播月份，减少事实表扫描量。
  select
    cast(d.dt as varchar) as dt,
    cast(d.ayyuid as varchar) as luid,
    max(cast(d.nickname as varchar)) as nickname,
    avg(coalesce(cast(d.acu as double), 0.0)) as day_acu
  from gamelive.dm_huya_ayyuid_detail_day d
  inner join salary_monthly s
    on cast(d.ayyuid as varchar) = s.luid
   and substr(cast(d.dt as varchar), 1, 7) = s.mth
  where cast(d.dt as varchar) between '2026-04-01' and '2026-09-30'
    and cast(d.gameid as varchar) = '5937'
  group by
    cast(d.dt as varchar),
    cast(d.ayyuid as varchar)
  having sum(coalesce(cast(d.live_mins as double), 0.0)) * 60 >= 15
),

anchor_month as (
  select
    substr(dt, 1, 7) as mth,
    luid,
    max(nickname) as nickname,
    count(*) as valid_days,
    avg(day_acu) as monthly_avg_acu
  from anchor_day
  group by
    substr(dt, 1, 7),
    luid
)

select
  a.luid as "站内主播UID",
  coalesce(s.anchor_nickname, a.nickname) as "站内主播昵称",
  a.mth as "结算月份",
  a.valid_days as "当月有效开播天数",
  cast(round(a.monthly_avg_acu, 2) as decimal(38,2)) as "当月有效日日均ACU",
  cast(round(s.salary_amount, 2) as decimal(38,2)) as "当月工资",
  case
    when a.monthly_avg_acu < 600 then '260-<600'
    when a.monthly_avg_acu < 900 then '600-<900'
    when a.monthly_avg_acu < 1200 then '900-<1200'
    when a.monthly_avg_acu < 1500 then '1200-<1500'
    when a.monthly_avg_acu < 1800 then '1500-<1800'
    when a.monthly_avg_acu < 2100 then '1800-<2100'
    when a.monthly_avg_acu < 2400 then '2100-<2400'
    when a.monthly_avg_acu < 2700 then '2400-<2700'
    when a.monthly_avg_acu < 3000 then '2700-<3000'
    else '3000及以上'
  end as "ACU分层"
from anchor_month a
inner join salary_monthly s
  on a.luid = s.luid
 and a.mth = s.mth
where a.monthly_avg_acu >= 260
order by
  a.monthly_avg_acu,
  a.luid,
  a.mth;
