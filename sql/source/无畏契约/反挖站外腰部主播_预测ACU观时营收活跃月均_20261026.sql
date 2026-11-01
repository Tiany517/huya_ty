-- 目的：按反挖站外腰部主播名单，计算以 2026-09 为截止月的近 3 月、近 6 月、
--       2026 年 1-9 月预测 ACU、预测观时、预测营收的活跃月均。
-- 数据源：zhgametemp.cys_huya_jingpin_fanwa_result
-- 表粒度：每个 dt 为月末分区快照，主播在该月最多保留一条“无畏契约”记录。
-- 平台口径：数仓抖音 pcode 为 douyin_web，名单中统一映射为 douyin。
-- 分母口径：
--   1. 只有 live_mins > 0 的月份才算该主播实际开播月份；
--   2. 每个指标再排除自身为 NULL 的月份；
--   3. 预测营收为空表示没有预测值，不按 0 处理。
-- 指标口径：
--   predict_acu       是月度预测 ACU 水平，不是月度累计值；
--   predict_viewhours 是月度预测观时，单位沿用源表；
--   predict_yingshou  是月度预测营收，单位沿用源表。

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

-- 主播月粒度：平台标准化、品类限定为“无畏契约”，并用 max 消除潜在重复行。
anchor_monthly as (
  select
    substr(cast(x.dt as varchar), 1, 7) as mth,
    case
      when lower(cast(x.pcode as varchar)) = 'douyin_web' then 'douyin'
      else lower(cast(x.pcode as varchar))
    end as pcode,
    cast(x.uid as varchar) as r_lid,
    max(cast(x.r_owner as varchar)) as latest_external_name,
    max(coalesce(try_cast(x.live_mins as bigint), 0)) as live_mins,
    max(try_cast(x.predict_acu as double)) as predict_acu,
    max(try_cast(x.predict_viewhours as double)) as predict_viewhours,
    max(try_cast(x.predict_yingshou as double)) as predict_yingshou
  from zhgametemp.cys_huya_jingpin_fanwa_result x
  inner join targets t
    on case
         when lower(cast(x.pcode as varchar)) = 'douyin_web' then 'douyin'
         else lower(cast(x.pcode as varchar))
       end = t.pcode
   and cast(x.uid as varchar) = cast(t.r_lid as varchar)
  where substr(cast(x.dt as varchar), 1, 7) between '2026-01' and '2026-09'
    and cast(x.r_category as varchar) = '无畏契约'
  group by
    substr(cast(x.dt as varchar), 1, 7),
    case
      when lower(cast(x.pcode as varchar)) = 'douyin_web' then 'douyin'
      else lower(cast(x.pcode as varchar))
    end,
    cast(x.uid as varchar)
),

-- 只保留实际开播月份。live_mins 为空或为 0 的月份不进入活跃月均分母。
active_anchor_monthly as (
  select *
  from anchor_monthly
  where live_mins > 0
),

-- 主播窗口指标：分母为该主播窗口内实际开播、且该指标有预测记录的月份数。
anchor_metrics as (
  select
    pcode,
    r_lid,
    max_by(
      latest_external_name,
      if(latest_external_name is null, null, mth)
    ) as latest_external_name,

    -- 近 3 月：2026-07 至 2026-09
    count(if(mth between '2026-07' and '2026-09', 1, null)) as near3_live_months,
    count(if(mth between '2026-07' and '2026-09' and predict_acu is not null, 1, null)) as near3_acu_pred_months,
    avg(if(mth between '2026-07' and '2026-09', predict_acu, null)) as near3_avg_predict_acu,
    count(if(mth between '2026-07' and '2026-09' and predict_viewhours is not null, 1, null)) as near3_viewhours_pred_months,
    avg(if(mth between '2026-07' and '2026-09', predict_viewhours, null)) as near3_avg_predict_viewhours,
    count(if(mth between '2026-07' and '2026-09' and predict_yingshou is not null, 1, null)) as near3_yingshou_pred_months,
    avg(if(mth between '2026-07' and '2026-09', predict_yingshou, null)) as near3_avg_predict_yingshou,

    -- 近 6 月：2026-04 至 2026-09
    count(if(mth between '2026-04' and '2026-09', 1, null)) as near6_live_months,
    count(if(mth between '2026-04' and '2026-09' and predict_acu is not null, 1, null)) as near6_acu_pred_months,
    avg(if(mth between '2026-04' and '2026-09', predict_acu, null)) as near6_avg_predict_acu,
    count(if(mth between '2026-04' and '2026-09' and predict_viewhours is not null, 1, null)) as near6_viewhours_pred_months,
    avg(if(mth between '2026-04' and '2026-09', predict_viewhours, null)) as near6_avg_predict_viewhours,
    count(if(mth between '2026-04' and '2026-09' and predict_yingshou is not null, 1, null)) as near6_yingshou_pred_months,
    avg(if(mth between '2026-04' and '2026-09', predict_yingshou, null)) as near6_avg_predict_yingshou,

    -- 2026 年 1-9 月
    count(if(mth between '2026-01' and '2026-09', 1, null)) as ytd_live_months,
    count(if(mth between '2026-01' and '2026-09' and predict_acu is not null, 1, null)) as ytd_acu_pred_months,
    avg(if(mth between '2026-01' and '2026-09', predict_acu, null)) as ytd_avg_predict_acu,
    count(if(mth between '2026-01' and '2026-09' and predict_viewhours is not null, 1, null)) as ytd_viewhours_pred_months,
    avg(if(mth between '2026-01' and '2026-09', predict_viewhours, null)) as ytd_avg_predict_viewhours,
    count(if(mth between '2026-01' and '2026-09' and predict_yingshou is not null, 1, null)) as ytd_yingshou_pred_months,
    avg(if(mth between '2026-01' and '2026-09', predict_yingshou, null)) as ytd_avg_predict_yingshou
  from active_anchor_monthly
  group by pcode, r_lid
)

select
  t.order_no as "序号",
  if(t.pcode = 'douyin', 'douyin_web', t.pcode) as "平台",
  t.r_lid as "主播ID",
  t.list_anchor_name as "名单主播名称",
  m.latest_external_name as "站外最新主播名称",

  coalesce(m.near3_live_months, 0) as "近3月实际开播月份数",
  coalesce(m.near3_acu_pred_months, 0) as "近3月ACU有预测月份数",
  cast(round(m.near3_avg_predict_acu, 2) as decimal(38,2)) as "近3月预测ACU活跃月均",
  coalesce(m.near3_viewhours_pred_months, 0) as "近3月观时有预测月份数",
  cast(round(m.near3_avg_predict_viewhours, 2) as decimal(38,2)) as "近3月预测观时活跃月均",
  coalesce(m.near3_yingshou_pred_months, 0) as "近3月营收有预测月份数",
  cast(round(m.near3_avg_predict_yingshou, 2) as decimal(38,2)) as "近3月预测营收活跃月均",

  coalesce(m.near6_live_months, 0) as "近6月实际开播月份数",
  coalesce(m.near6_acu_pred_months, 0) as "近6月ACU有预测月份数",
  cast(round(m.near6_avg_predict_acu, 2) as decimal(38,2)) as "近6月预测ACU活跃月均",
  coalesce(m.near6_viewhours_pred_months, 0) as "近6月观时有预测月份数",
  cast(round(m.near6_avg_predict_viewhours, 2) as decimal(38,2)) as "近6月预测观时活跃月均",
  coalesce(m.near6_yingshou_pred_months, 0) as "近6月营收有预测月份数",
  cast(round(m.near6_avg_predict_yingshou, 2) as decimal(38,2)) as "近6月预测营收活跃月均",

  coalesce(m.ytd_live_months, 0) as "1至9月实际开播月份数",
  coalesce(m.ytd_acu_pred_months, 0) as "1至9月ACU有预测月份数",
  cast(round(m.ytd_avg_predict_acu, 2) as decimal(38,2)) as "1至9月预测ACU活跃月均",
  coalesce(m.ytd_viewhours_pred_months, 0) as "1至9月观时有预测月份数",
  cast(round(m.ytd_avg_predict_viewhours, 2) as decimal(38,2)) as "1至9月预测观时活跃月均",
  coalesce(m.ytd_yingshou_pred_months, 0) as "1至9月营收有预测月份数",
  cast(round(m.ytd_avg_predict_yingshou, 2) as decimal(38,2)) as "1至9月预测营收活跃月均"
from targets t
left join anchor_metrics m
  on t.pcode = m.pcode
 and cast(t.r_lid as varchar) = cast(m.r_lid as varchar)
order by t.order_no;
