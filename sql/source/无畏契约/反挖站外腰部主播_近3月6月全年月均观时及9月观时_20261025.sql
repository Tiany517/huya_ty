-- 目的：按反挖站外腰部主播名单，计算以2026-09为截止月的近3月、近6月、
--       2026年1-9月月均观时，并单独输出2026年9月观时。
-- 数据源：zhgametemp.yty_jingpin_anchor_vaild_dau
-- 上游：gamelive.dm_mkt_rowner_day
-- 口径：watch_min = 站外有效ACU * 直播分钟数，单位为人·分钟；
--       月均观时 = 窗口内 sum(watch_min) / 固定月份数 / 60，单位小时；
--       近3月分母3、近6月分母6、1-9月分母9；无记录月份按0计入。
-- 平台映射：名单 douyin_web -> 数仓 douyin；bilibili、douyu 保持同名。
-- 品类：r_category = '无畏契约'。

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

-- 站外主播日粒度：保留实际观时字段，并消除潜在重复行
daily_anchor as (
  select
    dt,
    lower(pcode) as pcode,
    cast(r_lid as varchar) as r_lid,
    max(r_owner) as r_owner,
    sum(watch_min) as watch_min,
    sum(live_mins) as live_mins
  from zhgametemp.yty_jingpin_anchor_vaild_dau
  where dt between '2026-01-01' and '2026-09-30'
    and lower(pcode) in ('douyin','bilibili','douyu')
    and r_category = '无畏契约'
    and watch_min is not null
  group by
    dt,
    lower(pcode),
    cast(r_lid as varchar)
),

-- 主播窗口指标：同时保留日历摊薄（固定3/6/9个月）和活跃月（实际有记录月份）两种口径
anchor_metrics as (
  select
    pcode,
    r_lid,
    max_by(r_owner, dt) as latest_external_name,
    sum(if(dt between '2026-09-01' and '2026-09-30', live_mins, 0)) / 60.0 as sep_live_hours,
    sum(if(dt between '2026-09-01' and '2026-09-30', live_mins, 0)) / 30.0 / 60.0 as sep_avg_daily_live_hours,
    count(distinct if(dt between '2026-07-01' and '2026-09-30', substr(dt,1,7), null)) as near3_record_months,
    sum(if(dt between '2026-07-01' and '2026-09-30', live_mins, 0)) / 60.0 as near3_total_live_hours,
    sum(if(dt between '2026-07-01' and '2026-09-30', live_mins, 0)) / 3.0 / 60.0 as near3_monthly_avg_live_hours,
    sum(if(dt between '2026-07-01' and '2026-09-30', live_mins, 0)) / 60.0
      / nullif(count(distinct if(dt between '2026-07-01' and '2026-09-30', substr(dt,1,7), null)), 0) as near3_active_month_avg_live_hours,
    sum(if(dt between '2026-07-01' and '2026-09-30', watch_min, 0)) / 60.0 as near3_total_watch_hours,
    sum(if(dt between '2026-07-01' and '2026-09-30', watch_min, 0)) / 3.0 / 60.0 as near3_monthly_avg_watch_hours,
    sum(if(dt between '2026-07-01' and '2026-09-30', watch_min, 0)) / 60.0
      / nullif(count(distinct if(dt between '2026-07-01' and '2026-09-30', substr(dt,1,7), null)), 0) as near3_active_month_avg_watch_hours,
    count(distinct if(dt between '2026-04-01' and '2026-09-30', substr(dt,1,7), null)) as near6_record_months,
    sum(if(dt between '2026-04-01' and '2026-09-30', live_mins, 0)) / 60.0 as near6_total_live_hours,
    sum(if(dt between '2026-04-01' and '2026-09-30', live_mins, 0)) / 6.0 / 60.0 as near6_monthly_avg_live_hours,
    sum(if(dt between '2026-04-01' and '2026-09-30', live_mins, 0)) / 60.0
      / nullif(count(distinct if(dt between '2026-04-01' and '2026-09-30', substr(dt,1,7), null)), 0) as near6_active_month_avg_live_hours,
    sum(if(dt between '2026-04-01' and '2026-09-30', watch_min, 0)) / 60.0 as near6_total_watch_hours,
    sum(if(dt between '2026-04-01' and '2026-09-30', watch_min, 0)) / 6.0 / 60.0 as near6_monthly_avg_watch_hours,
    sum(if(dt between '2026-04-01' and '2026-09-30', watch_min, 0)) / 60.0
      / nullif(count(distinct if(dt between '2026-04-01' and '2026-09-30', substr(dt,1,7), null)), 0) as near6_active_month_avg_watch_hours,
    count(distinct substr(dt,1,7)) as ytd_record_months,
    sum(live_mins) / 60.0 as ytd_total_live_hours,
    sum(live_mins) / 9.0 / 60.0 as ytd_monthly_avg_live_hours,
    sum(live_mins) / 60.0 / nullif(count(distinct substr(dt,1,7)), 0) as ytd_active_month_avg_live_hours,
    sum(watch_min) / 60.0 as ytd_total_watch_hours,
    sum(watch_min) / 9.0 / 60.0 as ytd_monthly_avg_watch_hours,
    sum(watch_min) / 60.0 / nullif(count(distinct substr(dt,1,7)), 0) as ytd_active_month_avg_watch_hours,
    count(distinct if(dt between '2026-09-01' and '2026-09-30', dt, null)) as sep_record_days,
    sum(if(dt between '2026-09-01' and '2026-09-30', watch_min, 0)) as sep_watch_minutes,
    sum(if(dt between '2026-09-01' and '2026-09-30', watch_min, 0)) / 60.0 as sep_watch_hours
  from daily_anchor
  group by pcode, r_lid
),

-- 日ACU口径：同一主播同日多条记录按开播时长加权；
-- 抖音/快手开播分钟使用hour_cnt*60，其他平台使用live_mins。
-- 日ACU = sum(开播分钟×有效ACU) / sum(开播分钟)。
acu_row as (
  select
    cast(d.dt as varchar) as dt,
    case
      when cast(d.pcode as varchar) = 'douyin_web' then 'douyin'
      else cast(d.pcode as varchar)
    end as pcode,
    cast(d.r_lid as varchar) as r_lid,
    sum(
      case
        when cast(d.pcode as varchar) in ('douyin_web','douyin','kuaishou')
          then coalesce(try_cast(d.hour_cnt as double), 0.0) * 60
        else coalesce(try_cast(d.live_mins as double), 0.0)
      end
    ) as live_mins,
    sum(
      case
        when cast(d.pcode as varchar) in ('douyin_web','douyin','kuaishou')
          then coalesce(try_cast(d.hour_cnt as double), 0.0) * 60
        else coalesce(try_cast(d.live_mins as double), 0.0)
      end
      * coalesce(try_cast(element_at(d.ext, 'vaild_acu') as double), 0.0)
    ) as watch_mins
  from gamelive.dm_mkt_rowner_day d
  inner join (select distinct pcode, r_lid from targets) tk
    on case
         when cast(d.pcode as varchar) = 'douyin_web' then 'douyin'
         else cast(d.pcode as varchar)
       end = tk.pcode
   and cast(d.r_lid as varchar) = tk.r_lid
  where d.dt between '2026-01-01' and '2026-09-30'
    and cast(d.pcode as varchar) in ('huya','douyin','douyin_web','douyu','bilibili','kuaishou')
    and coalesce(nullif(cast(d.cate1 as varchar),''),cast(d.r_category as varchar)) = '无畏契约'
  group by
    cast(d.dt as varchar),
    case
      when cast(d.pcode as varchar) = 'douyin_web' then 'douyin'
      else cast(d.pcode as varchar)
    end,
    cast(d.r_lid as varchar)
),
valid_acu_day as (
  select
    dt,
    pcode,
    r_lid,
    watch_mins / nullif(live_mins, 0) as valid_acu,
    live_mins
  from acu_row
  where live_mins >= 15
    and watch_mins > 0
),
acu_metrics as (
  select
    pcode,
    r_lid,
    avg(if(dt between '2026-07-01' and '2026-09-30', valid_acu, null)) as near3_daily_avg_acu,
    count_if(dt between '2026-07-01' and '2026-09-30') as near3_acu_days,
    avg(if(dt between '2026-04-01' and '2026-09-30', valid_acu, null)) as near6_daily_avg_acu,
    count_if(dt between '2026-04-01' and '2026-09-30') as near6_acu_days,
    avg(valid_acu) as ytd_daily_avg_acu,
    count(*) as ytd_acu_days,
    avg(if(dt between '2026-09-01' and '2026-09-30', valid_acu, null)) as sep_daily_avg_acu,
    count_if(dt between '2026-09-01' and '2026-09-30') as sep_acu_days
  from valid_acu_day
  group by pcode, r_lid
)

select
  t.order_no as "序号",
  if(t.pcode = 'douyin', 'douyin_web', t.pcode) as "平台",
  t.r_lid as "主播ID",
  t.list_anchor_name as "名单主播名称",
  m.latest_external_name as "站外最新主播名称",
  -- 9月
  coalesce(m.sep_record_days, 0) as "9月有记录天数",
  cast(round(coalesce(m.sep_live_hours, 0), 2) as decimal(38,2)) as "9月直播时长_小时",
  cast(round(coalesce(m.sep_avg_daily_live_hours, 0), 2) as decimal(38,2)) as "9月日均直播时长_小时",
  cast(round(coalesce(m.sep_watch_minutes, 0), 2) as decimal(38,2)) as "9月真实观时_分钟",
  cast(round(coalesce(m.sep_watch_hours, 0), 2) as decimal(38,2)) as "9月真实观时_小时",
  cast(round(coalesce(a.sep_daily_avg_acu, 0), 2) as decimal(38,2)) as "9月月日均ACU",
  coalesce(a.sep_acu_days, 0) as "9月ACU计算天数",
  -- 近3月
  coalesce(m.near3_record_months, 0) as "近3月有记录月份数",
  cast(round(coalesce(m.near3_total_live_hours, 0), 2) as decimal(38,2)) as "近3月直播总时长_小时",
  cast(round(coalesce(m.near3_monthly_avg_live_hours, 0), 2) as decimal(38,2)) as "近3月日历摊薄月均直播时长_小时",
  cast(round(coalesce(m.near3_active_month_avg_live_hours, 0), 2) as decimal(38,2)) as "近3月活跃月均直播时长_小时",
  cast(round(coalesce(m.near3_total_watch_hours, 0), 2) as decimal(38,2)) as "近3月总观时_小时",
  cast(round(coalesce(m.near3_monthly_avg_watch_hours, 0), 2) as decimal(38,2)) as "近3月日历摊薄月均观时_小时",
  cast(round(coalesce(m.near3_active_month_avg_watch_hours, 0), 2) as decimal(38,2)) as "近3月活跃月均观时_小时",
  cast(round(coalesce(a.near3_daily_avg_acu, 0), 2) as decimal(38,2)) as "近3月月日均ACU",
  coalesce(a.near3_acu_days, 0) as "近3月ACU计算天数",
  -- 近6月
  coalesce(m.near6_record_months, 0) as "近6月有记录月份数",
  cast(round(coalesce(m.near6_total_live_hours, 0), 2) as decimal(38,2)) as "近6月直播总时长_小时",
  cast(round(coalesce(m.near6_monthly_avg_live_hours, 0), 2) as decimal(38,2)) as "近6月日历摊薄月均直播时长_小时",
  cast(round(coalesce(m.near6_active_month_avg_live_hours, 0), 2) as decimal(38,2)) as "近6月活跃月均直播时长_小时",
  cast(round(coalesce(m.near6_total_watch_hours, 0), 2) as decimal(38,2)) as "近6月总观时_小时",
  cast(round(coalesce(m.near6_monthly_avg_watch_hours, 0), 2) as decimal(38,2)) as "近6月日历摊薄月均观时_小时",
  cast(round(coalesce(m.near6_active_month_avg_watch_hours, 0), 2) as decimal(38,2)) as "近6月活跃月均观时_小时",
  cast(round(coalesce(a.near6_daily_avg_acu, 0), 2) as decimal(38,2)) as "近6月月日均ACU",
  coalesce(a.near6_acu_days, 0) as "近6月ACU计算天数",
  -- 1至9月
  coalesce(m.ytd_record_months, 0) as "1至9月有记录月份数",
  cast(round(coalesce(m.ytd_total_live_hours, 0), 2) as decimal(38,2)) as "1至9月直播总时长_小时",
  cast(round(coalesce(m.ytd_monthly_avg_live_hours, 0), 2) as decimal(38,2)) as "1至9月日历摊薄月均直播时长_小时",
  cast(round(coalesce(m.ytd_active_month_avg_live_hours, 0), 2) as decimal(38,2)) as "1至9月活跃月均直播时长_小时",
  cast(round(coalesce(m.ytd_total_watch_hours, 0), 2) as decimal(38,2)) as "1至9月总观时_小时",
  cast(round(coalesce(m.ytd_monthly_avg_watch_hours, 0), 2) as decimal(38,2)) as "1至9月日历摊薄月均观时_小时",
  cast(round(coalesce(m.ytd_active_month_avg_watch_hours, 0), 2) as decimal(38,2)) as "1至9月活跃月均观时_小时",
  cast(round(coalesce(a.ytd_daily_avg_acu, 0), 2) as decimal(38,2)) as "1至9月月日均ACU",
  coalesce(a.ytd_acu_days, 0) as "1至9月ACU计算天数"
from targets t
left join anchor_metrics m
  on t.pcode = m.pcode
 and t.r_lid = m.r_lid
left join acu_metrics a
  on t.pcode = a.pcode
 and t.r_lid = a.r_lid
order by t.order_no;
