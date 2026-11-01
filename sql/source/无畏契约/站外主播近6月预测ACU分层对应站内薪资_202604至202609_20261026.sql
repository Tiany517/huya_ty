-- 目的：将 40 名站外候选主播按近 6 月预测日均 ACU 每 100 分档，
--       找到近 6 月同样在虎牙直播“无畏契约”且 ACU 落在同一档位的站内主播，
--       汇总这些站内主播在 2026-04 至 2026-09 的平均工资。
--
-- 站外 ACU：
--   1. 优先使用 zhgametemp.cys_huya_jingpin_fanwa_result.predict_acu；
--   2. 某月无预测 ACU 时，使用该主播当月真实 ACU × 1.04；
--   3. 只使用主播实际开播的月份。
--
-- 站内 ACU：
--   虎牙“无畏契约”主播，按日有效 ACU 计算月日均 ACU，再对实际开播月份求近 6 月平均。
--
-- 工资：
--   1. bp.md_dwd_anchor_salary 的 settlement_date 为月分区日期；
--   2. 当前近 6 个月为 2026-04 至 2026-09；
--   3. 同一主播同月可能存在多条费用记录，先汇总 final_amount，再计算月工资；
--   4. 只取 game_name='无畏契约'、role='主播'；
--   5. “有发薪主播”指近 6 月 final_amount 合计大于 0 的主播。

with targets(order_no, pcode, r_lid, list_anchor_name) as (
  values
    (1, 'douyin','23406469421','TryTryz（无畏契约）'),
    (2, 'bilibili','9645651','KMD_'),
    (3, 'douyin','130206898427','荣誉无畏契约'),
    (4, 'bilibili','14361477','憨疯SaramandE'),
    (5, 'bilibili','38833141','龟龟叁叁'),
    (6, 'bilibili','46768206','Bennign笨奶'),
    (7, 'bilibili','413464149','妮蔻Neekoko'),
    (8, 'bilibili','263249641','丐伦菌'),
    (9, 'bilibili','28602593','小辞炒糍粑'),
    (10, 'douyin','843398854662','讲过往'),
    (11, 'douyin','435345554204','小辉（无畏契约）'),
    (12, 'bilibili','1665135150','一个瓦瓦小镇的保安'),
    (13, 'bilibili','3493265470917588','谋生者白言'),
    (14, 'bilibili','17358642','解说奶爸'),
    (15, 'bilibili','1266203568','Yuko咩咩'),
    (16, 'douyin','386003334438','企鹅（无畏契约欧美解说）'),
    (17, 'douyin','942743272087','从玲开始的异世界/三笙喵SSMeow电竞'),
    (18, 'douyin','592608957208','Kill'),
    (19, 'bilibili','8319463','比比_Sama'),
    (20, 'douyin','61409166405','K1rss（无畏契约）'),
    (21, 'douyin','509958398422','杰米GEmini'),
    (22, 'douyin','250480858431','小民111'),
    (23, 'douyin','183812264090','Zoomer（无畏契约）'),
    (24, 'douyin','50942209695','绿泡泡Reyna（无畏契约）'),
    (25, 'douyin','7967780949','胡提（冲千分）'),
    (26, 'douyin','363275355623','Code（无畏契约）'),
    (27, 'bilibili','503040864','是Winter喵'),
    (28, 'douyin','76112910063','7in（无畏契约）'),
    (29, 'douyin','457744421791','梦火'),
    (30, 'bilibili','275981','小绝'),
    (31, 'douyin','626168588979','暴0战士(无畏契约）'),
    (32, 'bilibili','14272337','Yommyko'),
    (33, 'douyin','333615397345','章不是蟑'),
    (34, 'bilibili','565365831','0verthink1NG'),
    (35, 'bilibili','3546691244395002','希咩咩Kaguya'),
    (36, 'douyin','686375449707','忧郁的雨'),
    (37, 'douyin','474077973022','AQ S1Mon'),
    (38, 'bilibili','1822269711','阿辙azhe'),
    (39, 'douyu','2535858','驴酱阿松'),
    (40, 'douyin','219926279508','王木研')
),

-- 站外预测月粒度：predict_acu 是月度预测 ACU 水平。
external_predict_monthly as (
  select
    substr(cast(x.dt as varchar), 1, 7) as mth,
    case
      when lower(cast(x.pcode as varchar)) = 'douyin_web' then 'douyin'
      else lower(cast(x.pcode as varchar))
    end as pcode,
    cast(x.uid as varchar) as r_lid,
    max(coalesce(try_cast(x.live_mins as bigint), 0)) as live_mins,
    max(try_cast(x.predict_acu as double)) as predict_acu
  from zhgametemp.cys_huya_jingpin_fanwa_result x
  inner join targets t
    on case
         when lower(cast(x.pcode as varchar)) = 'douyin_web' then 'douyin'
         else lower(cast(x.pcode as varchar))
       end = t.pcode
   and cast(x.uid as varchar) = cast(t.r_lid as varchar)
  where substr(cast(x.dt as varchar), 1, 7) between '2026-04' and '2026-09'
    and cast(x.r_category as varchar) = '无畏契约'
  group by
    1,
    2,
    3
),

-- 站外真实日粒度：抖音、快手使用 hour_cnt×60，其他平台使用 live_mins。
external_actual_day as (
  select
    cast(d.dt as varchar) as dt,
    case
      when lower(cast(d.pcode as varchar)) = 'douyin_web' then 'douyin'
      else lower(cast(d.pcode as varchar))
    end as pcode,
    cast(d.r_lid as varchar) as r_lid,
    sum(
      case
        when lower(cast(d.pcode as varchar)) in ('douyin_web','douyin','kuaishou')
          then coalesce(try_cast(d.hour_cnt as double), 0.0) * 60
        else coalesce(try_cast(d.live_mins as double), 0.0)
      end
    ) as live_mins,
    sum(
      case
        when lower(cast(d.pcode as varchar)) in ('douyin_web','douyin','kuaishou')
          then coalesce(try_cast(d.hour_cnt as double), 0.0) * 60
        else coalesce(try_cast(d.live_mins as double), 0.0)
      end
      * coalesce(try_cast(element_at(d.ext, 'vaild_acu') as double), 0.0)
    ) as watch_mins
  from gamelive.dm_mkt_rowner_day d
  inner join targets t
    on case
         when lower(cast(d.pcode as varchar)) = 'douyin_web' then 'douyin'
         else lower(cast(d.pcode as varchar))
       end = t.pcode
   and cast(d.r_lid as varchar) = cast(t.r_lid as varchar)
  where d.dt between '2026-04-01' and '2026-09-30'
    and lower(cast(d.pcode as varchar)) in (
      'douyin_web','douyin','bilibili','douyu','kuaishou'
    )
    and coalesce(
      nullif(cast(d.cate1 as varchar), ''),
      cast(d.r_category as varchar)
    ) = '无畏契约'
  group by
    1,
    2,
    3
),

external_valid_day as (
  select
    dt,
    pcode,
    r_lid,
    watch_mins / nullif(live_mins, 0) as valid_acu,
    live_mins
  from external_actual_day
  where live_mins >= 15
    and watch_mins > 0
),

external_actual_monthly as (
  select
    substr(dt, 1, 7) as mth,
    pcode,
    r_lid,
    avg(valid_acu) as actual_acu
  from external_valid_day
  group by
    substr(dt, 1, 7),
    pcode,
    r_lid
),

-- 外部主播有效月份取“真实开播月份”与“有预测开播月份”的并集。
external_month_keys as (
  select mth, pcode, r_lid
  from external_actual_monthly
  union
  select mth, pcode, r_lid
  from external_predict_monthly
  where live_mins > 0
),

external_effective_monthly as (
  select
    k.mth,
    k.pcode,
    k.r_lid,
    p.predict_acu,
    a.actual_acu,
    coalesce(
      p.predict_acu,
      a.actual_acu * 1.04
    ) as effective_acu,
    if(p.predict_acu is null and a.actual_acu is not null, 1, 0) as used_actual_fallback
  from external_month_keys k
  left join external_predict_monthly p
    on k.mth = p.mth
   and k.pcode = p.pcode
   and k.r_lid = p.r_lid
  left join external_actual_monthly a
    on k.mth = a.mth
   and k.pcode = a.pcode
   and k.r_lid = a.r_lid
),

external_anchor_acu as (
  select
    pcode,
    r_lid,
    count(if(effective_acu is not null, 1, null)) as acu_months,
    sum(used_actual_fallback) as actual_fallback_months,
    avg(effective_acu) as near6_benchmark_acu
  from external_effective_monthly
  group by
    pcode,
    r_lid
),

external_benchmark as (
  select
    t.order_no,
    t.pcode,
    t.r_lid,
    t.list_anchor_name,
    e.acu_months,
    e.actual_fallback_months,
    e.near6_benchmark_acu,
    case
      when e.near6_benchmark_acu is null then null
      when e.near6_benchmark_acu < 100 then 0
      when e.near6_benchmark_acu < 200 then 100
      when e.near6_benchmark_acu < 300 then 200
      when e.near6_benchmark_acu < 400 then 300
      when e.near6_benchmark_acu < 500 then 400
      when e.near6_benchmark_acu < 600 then 500
      when e.near6_benchmark_acu < 700 then 600
      when e.near6_benchmark_acu < 800 then 700
      when e.near6_benchmark_acu < 900 then 800
      when e.near6_benchmark_acu < 1000 then 900
      when e.near6_benchmark_acu < 1100 then 1000
      when e.near6_benchmark_acu < 1200 then 1100
      when e.near6_benchmark_acu < 1300 then 1200
      when e.near6_benchmark_acu < 1400 then 1300
      when e.near6_benchmark_acu < 1500 then 1400
      when e.near6_benchmark_acu < 1600 then 1500
      when e.near6_benchmark_acu < 1700 then 1600
      when e.near6_benchmark_acu < 1800 then 1700
      when e.near6_benchmark_acu < 1900 then 1800
      when e.near6_benchmark_acu < 2000 then 1900
      when e.near6_benchmark_acu < 2100 then 2000
      when e.near6_benchmark_acu < 2200 then 2100
      when e.near6_benchmark_acu < 2300 then 2200
      when e.near6_benchmark_acu < 2400 then 2300
      when e.near6_benchmark_acu < 2500 then 2400
      when e.near6_benchmark_acu < 2600 then 2500
      when e.near6_benchmark_acu < 2700 then 2600
      when e.near6_benchmark_acu < 2800 then 2700
      when e.near6_benchmark_acu < 2900 then 2800
      when e.near6_benchmark_acu < 3000 then 2900
      when e.near6_benchmark_acu < 3100 then 3000
      when e.near6_benchmark_acu < 3200 then 3100
      when e.near6_benchmark_acu < 3300 then 3200
      when e.near6_benchmark_acu < 3400 then 3300
      when e.near6_benchmark_acu < 3500 then 3400
      when e.near6_benchmark_acu < 3600 then 3500
      when e.near6_benchmark_acu < 3700 then 3600
      when e.near6_benchmark_acu < 3800 then 3700
      when e.near6_benchmark_acu < 3900 then 3800
      when e.near6_benchmark_acu < 4000 then 3900
      else 4000
    end as tier_lower
  from targets t
  left join external_anchor_acu e
    on t.pcode = e.pcode
   and cast(t.r_lid as varchar) = cast(e.r_lid as varchar)
),

external_by_tier as (
  select
    tier_lower,
    count(*) as external_anchor_cnt,
    avg(near6_benchmark_acu) as external_avg_acu,
    array_join(array_agg(list_anchor_name), '、') as external_anchor_names
  from external_benchmark
  where tier_lower is not null
  group by tier_lower
),

-- 站内虎牙真实日粒度：有效日 ACU 按直播分钟加权。
internal_actual_day as (
  select
    cast(d.dt as varchar) as dt,
    cast(d.r_lid as varchar) as r_lid,
    sum(coalesce(try_cast(d.live_mins as double), 0.0)) as live_mins,
    sum(
      coalesce(try_cast(d.live_mins as double), 0.0)
      * coalesce(try_cast(element_at(d.ext, 'vaild_acu') as double), 0.0)
    ) as watch_mins
  from gamelive.dm_mkt_rowner_day d
  where d.dt between '2026-04-01' and '2026-09-30'
    and lower(cast(d.pcode as varchar)) = 'huya'
    and coalesce(
      nullif(cast(d.cate1 as varchar), ''),
      cast(d.r_category as varchar)
    ) = '无畏契约'
  group by
    1,
    2
),

internal_valid_day as (
  select
    dt,
    r_lid,
    watch_mins / nullif(live_mins, 0) as valid_acu,
    live_mins
  from internal_actual_day
  where live_mins >= 15
    and watch_mins > 0
),

internal_actual_monthly as (
  select
    substr(dt, 1, 7) as mth,
    r_lid,
    avg(valid_acu) as monthly_avg_acu
  from internal_valid_day
  group by
    substr(dt, 1, 7),
    r_lid
),

internal_anchor_acu as (
  select
    r_lid,
    count(*) as active_months,
    avg(monthly_avg_acu) as near6_actual_acu
  from internal_actual_monthly
  group by r_lid
),

internal_benchmark as (
  select
    r_lid,
    active_months,
    near6_actual_acu,
    case
      when near6_actual_acu < 100 then 0
      when near6_actual_acu < 200 then 100
      when near6_actual_acu < 300 then 200
      when near6_actual_acu < 400 then 300
      when near6_actual_acu < 500 then 400
      when near6_actual_acu < 600 then 500
      when near6_actual_acu < 700 then 600
      when near6_actual_acu < 800 then 700
      when near6_actual_acu < 900 then 800
      when near6_actual_acu < 1000 then 900
      when near6_actual_acu < 1100 then 1000
      when near6_actual_acu < 1200 then 1100
      when near6_actual_acu < 1300 then 1200
      when near6_actual_acu < 1400 then 1300
      when near6_actual_acu < 1500 then 1400
      when near6_actual_acu < 1600 then 1500
      when near6_actual_acu < 1700 then 1600
      when near6_actual_acu < 1800 then 1700
      when near6_actual_acu < 1900 then 1800
      when near6_actual_acu < 2000 then 1900
      when near6_actual_acu < 2100 then 2000
      when near6_actual_acu < 2200 then 2100
      when near6_actual_acu < 2300 then 2200
      when near6_actual_acu < 2400 then 2300
      when near6_actual_acu < 2500 then 2400
      when near6_actual_acu < 2600 then 2500
      when near6_actual_acu < 2700 then 2600
      when near6_actual_acu < 2800 then 2700
      when near6_actual_acu < 2900 then 2800
      when near6_actual_acu < 3000 then 2900
      when near6_actual_acu < 3100 then 3000
      when near6_actual_acu < 3200 then 3100
      when near6_actual_acu < 3300 then 3200
      when near6_actual_acu < 3400 then 3300
      when near6_actual_acu < 3500 then 3400
      when near6_actual_acu < 3600 then 3500
      when near6_actual_acu < 3700 then 3600
      when near6_actual_acu < 3800 then 3700
      when near6_actual_acu < 3900 then 3800
      when near6_actual_acu < 4000 then 3900
      else 4000
    end as tier_lower
  from internal_anchor_acu
),

-- 站内主播月工资：先把同月多条 final_amount 汇总成主播月工资。
salary_monthly as (
  select
    substr(cast(settlement_date as varchar), 1, 7) as mth,
    cast(uid as varchar) as uid,
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
),

salary_anchor_6m as (
  select
    uid,
    max(anchor_nickname) as anchor_nickname,
    sum(salary_amount) as salary_total_6m,
    count(*) as salary_record_months,
    count(if(salary_amount > 0, 1, null)) as positive_salary_months
  from salary_monthly
  group by uid
),

internal_salary_by_tier as (
  select
    b.tier_lower,
    count(distinct b.r_lid) as internal_matched_anchor_cnt,
    count(distinct if(s.salary_total_6m > 0, b.r_lid, null)) as internal_paid_anchor_cnt,
    array_join(array_agg(distinct s.anchor_nickname), '、') as internal_anchor_names,
    sum(s.salary_total_6m) as salary_total_6m,
    sum(s.positive_salary_months) as positive_salary_month_cnt,
    avg(b.near6_actual_acu) as internal_avg_acu,
    sum(s.salary_total_6m) / 6.0
      / nullif(count(distinct b.r_lid), 0) as avg_month_salary_all_matched,
    sum(s.salary_total_6m) / 6.0
      / nullif(count(distinct if(s.salary_total_6m > 0, b.r_lid, null)), 0) as avg_month_salary_paid_anchor,
    sum(s.salary_total_6m)
      / nullif(sum(s.positive_salary_months), 0) as avg_positive_month_salary
  from internal_benchmark b
  inner join salary_anchor_6m s
    on b.r_lid = s.uid
  group by b.tier_lower
),

tier_map(tier_lower, tier_order, acu_tier) as (
  values
    (0,1,'0-<100'),(100,2,'100-<200'),(200,3,'200-<300'),(300,4,'300-<400'),
    (400,5,'400-<500'),(500,6,'500-<600'),(600,7,'600-<700'),(700,8,'700-<800'),
    (800,9,'800-<900'),(900,10,'900-<1000'),(1000,11,'1000-<1100'),
    (1100,12,'1100-<1200'),(1200,13,'1200-<1300'),(1300,14,'1300-<1400'),
    (1400,15,'1400-<1500'),(1500,16,'1500-<1600'),(1600,17,'1600-<1700'),
    (1700,18,'1700-<1800'),(1800,19,'1800-<1900'),(1900,20,'1900-<2000'),
    (2000,21,'2000-<2100'),(2100,22,'2100-<2200'),(2200,23,'2200-<2300'),
    (2300,24,'2300-<2400'),(2400,25,'2400-<2500'),(2500,26,'2500-<2600'),
    (2600,27,'2600-<2700'),(2700,28,'2700-<2800'),(2800,29,'2800-<2900'),
    (2900,30,'2900-<3000'),(3000,31,'3000-<3100'),(3100,32,'3100-<3200'),
    (3200,33,'3200-<3300'),(3300,34,'3300-<3400'),(3400,35,'3400-<3500'),
    (3500,36,'3500-<3600'),(3600,37,'3600-<3700'),(3700,38,'3700-<3800'),
    (3800,39,'3800-<3900'),(3900,40,'3900-<4000'),(4000,41,'4000及以上')
)

select
  tm.acu_tier as "近6月预测日均ACU分层",
  coalesce(e.external_anchor_cnt, 0) as "站外主播数",
  cast(round(e.external_avg_acu, 2) as decimal(38,2)) as "站外平均ACU",
  e.external_anchor_names as "站外主播名单",
  coalesce(s.internal_matched_anchor_cnt, 0) as "站内匹配主播数",
  coalesce(s.internal_paid_anchor_cnt, 0) as "站内有发薪主播数",
  s.internal_anchor_names as "站内匹配主播名单",
  cast(round(s.internal_avg_acu, 2) as decimal(38,2)) as "站内平均ACU",
  cast(round(s.salary_total_6m, 2) as decimal(38,2)) as "近6月工资总额",
  cast(round(s.avg_month_salary_all_matched, 2) as decimal(38,2)) as "近6月人均月工资_含0发放主播",
  cast(round(s.avg_month_salary_paid_anchor, 2) as decimal(38,2)) as "近6月有发薪主播人均月工资",
  cast(round(s.avg_positive_month_salary, 2) as decimal(38,2)) as "有发薪月份人均月工资"
from tier_map tm
left join external_by_tier e
  on tm.tier_lower = e.tier_lower
left join internal_salary_by_tier s
  on tm.tier_lower = s.tier_lower
where coalesce(e.external_anchor_cnt, 0) > 0
order by tm.tier_order;
