-- ============================================================
-- AI工坊 × App版本：锁定「版本从头升到尾」的同一批用户，做同一人群的版本间对比
-- 时间窗口：2026-07-13 ~ 2026-09-14
-- 输出粒度：版本号一行（同一批用户在每个版本上的日均表现）
-- ============================================================
-- 【为什么这么做】
--   之前按「版本」横比时，每个版本对应的是不同的人（不同时间升级、不同活跃度），
--   版本差异和人群差异混在一起。这里改成锁定同一批人：只保留在观察期内
--   按顺序把 13.3.82 → 13.4.0 → 13.4.2 → 13.4.22 → 13.4.40 → 13.4.41 → 13.4.52 → 13.4.63
--   全部升过一遍的用户，看这批人在自己不同版本上的表现变化。人固定了，剩下的差异只能来自版本。
--
-- 【「从头到尾都升级了」怎么判定】
--   给 8 个版本按发布顺序编上序号 1~8，然后只留同时满足三条的用户：
--     1) 历史里没有出现过白名单以外的版本（避免版本序列被过滤成「假连续」）
--     2) 8 个序号全都出现过（count(distinct) = 8）
--     3) 版本序号从不回退（今天序号 < 昨天序号 的天数为 0）
--   序号不递减 + 8 个值全覆盖，等价于「按顺序一路升级、不跳版、不回退」。
--   比版本路径拼字符串简单，也不用 array_agg / array_join。
--
-- 【口径与限制（必须一起看）】
--   1. 曝光：调度表 zhgametemp.zty_ads_huya_ai_gift_user_detail_0901_v1 的 is_exposure，
--      按 (日期, ukey) 去重后的人天；转化率分母用曝光人天。
--   2. 支付与流水：revenue 表里 AI 礼物（ext['is_ai']='1' 且 play_type 非抽奖）的
--      支付人天与消费额，按 (日期, ukey) 归集，版本按付费当天的版本归属。
--   3. 输出是「日均」而不是合计：各版本段长度不同（7 天 ~ 11 天），合计不可比。
--   4. 曝光口径在 2026-09-01 有约 4 倍断崖（大盘 134.7 万 → 31.8 万）。
--      同一批人跨期也受它影响，「13.3.82~13.4.41」和「13.4.52~13.4.63」之间的
--      曝光与转化率差异要单独标注。
--   5. 这批人是「一路升级的活跃用户」，本身就是重度子集，结论只能代表他们，
--      不能外推到全体用户。先跑附1 看人数，只有几百人的话波动区间要先算出来。
--   6. 用户什么时候升级是他自己决定的，不是随机分组；所以这条结论要和
--      同日基准折算（方案一）互相印证，不要单独当因果证据用。
-- ============================================================

with candidate_user as (
    -- 预筛：只有在 13.4.63 段出现过的人才可能「升到尾」，先把候选池压小
    select distinct
        cast(s.ukey as varchar) as ukey
    from gamelive.dw_huya_session_level s
    where s.dt between '2026-09-08' and '2026-09-14'
      and s.product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
      and s.tag = 'product'
      and cast(s.iver as varchar) = '13.4.63'
      and s.ukey is not null
),

item_dim as (
    -- 每日道具维表：识别 AI 礼物与抽奖礼物
    select
        d.dt as dt,
        cast(d.item_id as varchar) as item_id,
        max(case when d.item_level = '礼物' and element_at(d.ext, 'is_ai') = '1' then 1 else 0 end) as is_ai,
        max(case when d.play_type in ('抽奖') then 1 else 0 end) as is_draw
    from gamelive.dim_huya_item_d_a d
    where d.dt between '2026-07-13' and '2026-09-14'
      and d.item_level = '礼物'
    group by
        d.dt,
        cast(d.item_id as varchar)
),

ai_gift_pay_user_day as (
    -- AI 礼物支付人天：人天粒度，带当天 AI 流水
    select
        r.dt as dt,
        cast(element_at(r.ext, 'ukey') as varchar) as ukey,
        sum(cast(r.user_consume_amount as double)) as ai_amount
    from gamelive.dws_huya_revenue_detail_d_i r
    inner join item_dim i
        on r.dt = i.dt
       and cast(r.item_id as varchar) = i.item_id
       and i.is_ai = 1
       and i.is_draw = 0
    where r.dt between '2026-07-13' and '2026-09-14'
      and r.consume_order_type = '礼物'
      and cast(r.user_consume_amount as double) > 0
      and r.user_uid is not null
      and lower(cast(r.user_uid as varchar)) not in ('0', 'other')
      and r.creator_uid is not null
      and r.order_time is not null
      and element_at(r.ext, 'ukey') is not null
      and lower(cast(element_at(r.ext, 'ukey') as varchar)) not in ('', '0', 'other')
    group by
        r.dt,
        cast(element_at(r.ext, 'ukey') as varchar)
),

funnel_user_day as (
    -- 调度表漏斗：人天粒度的 AI工坊曝光标记
    select
        t.dt as dt,
        cast(t.user_ukey as varchar) as ukey,
        max(case when t.is_exposure then 1 else 0 end) as is_exposure
    from zhgametemp.zty_ads_huya_ai_gift_user_detail_0901_v1 t
    where t.dt between '2026-07-13' and '2026-09-14'
      and t.user_ukey is not null
    group by
        t.dt,
        cast(t.user_ukey as varchar)
),

user_version_day as (
    -- 用户 × 天 的实际 App 版本；同一 ukey 同一天只保留一个版本
    -- 这一步刻意不限制版本号，保证版本序列不会被白名单过滤成「假连续」
    select
        s.dt as dt,
        cast(s.ukey as varchar) as ukey,
        max(cast(s.iver as varchar)) as iver
    from gamelive.dw_huya_session_level s
    where s.dt between '2026-07-13' and '2026-09-14'
      and s.product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
      and s.tag = 'product'
      and s.ukey is not null
      and s.iver is not null
      and cast(s.iver as varchar) not in ('', '0')
    group by
        s.dt,
        cast(s.ukey as varchar)
),

version_rank as (
    -- 候选池内用户的版本历史，把 8 个版本按发布顺序编上序号 1~8
    -- 其他 App 版本（13.2.x、13.5.x 等）序号为 NULL
    select
        d.ukey as ukey,
        d.dt as dt,
        d.iver as iver,
        case
            when d.iver = '13.3.82' then 1
            when d.iver = '13.4.0' then 2
            when d.iver = '13.4.2' then 3
            when d.iver = '13.4.22' then 4
            when d.iver = '13.4.40' then 5
            when d.iver = '13.4.41' then 6
            when d.iver = '13.4.52' then 7
            when d.iver = '13.4.63' then 8
        end as version_rank
    from user_version_day d
    inner join candidate_user c
        on d.ukey = c.ukey
),

clean_user as (
    -- 条件1：历史里出现任何白名单以外版本的用户直接剔除
    select
        d.ukey as ukey
    from version_rank d
    group by
        d.ukey
    having max(case when d.version_rank is null then 1 else 0 end) = 0
),

rank_ordered as (
    -- 按天排出每个用户的版本序号，用于判断有没有回退
    select
        d.ukey as ukey,
        d.dt as dt,
        d.version_rank as version_rank,
        lag(d.version_rank) over (partition by d.ukey order by d.dt) as prev_version_rank
    from version_rank d
    inner join clean_user u
        on d.ukey = u.ukey
),

user_check as (
    -- 条件2：8 个序号全覆盖（version_cnt = 8）
    -- 条件3：序号从不回退（rollback_day_cnt = 0）
    select
        o.ukey as ukey,
        count(distinct o.version_rank) as version_cnt,
        min(o.version_rank) as min_version_rank,
        max(o.version_rank) as max_version_rank,
        sum(
            case
                when o.prev_version_rank is not null and o.version_rank < o.prev_version_rank then 1
                else 0
            end
        ) as rollback_day_cnt,
        min(o.dt) as first_dt,
        max(o.dt) as last_dt
    from rank_ordered o
    group by
        o.ukey
),

full_upgrade_user as (
    -- 严格口径：按顺序一路升到尾的同一批用户
    select
        c.ukey as ukey,
        c.first_dt as first_dt,
        c.last_dt as last_dt
    from user_check c
    where c.version_cnt = 8
      and c.min_version_rank = 1
      and c.max_version_rank = 8
      and c.rollback_day_cnt = 0
),

user_day_detail as (
    -- 这批用户的人天明细：版本 + 曝光 + 支付 + 流水
    select
        d.iver as iver,
        d.ukey as ukey,
        d.dt as dt,
        case when u.is_exposure = 1 then 1 else 0 end as is_exposure,
        case when p.ukey is not null then 1 else 0 end as is_pay,
        coalesce(p.ai_amount, 0) as ai_amount
    from user_version_day d
    inner join full_upgrade_user f
        on d.ukey = f.ukey
    left join funnel_user_day u
        on d.dt = u.dt
       and d.ukey = u.ukey
    left join ai_gift_pay_user_day p
        on d.dt = p.dt
       and d.ukey = p.ukey
),

version_day_agg as (
    -- 版本 × 天：该批用户在当天的曝光人数 / 支付人数 / 流水（只算有曝光的天）
    select
        iver as iver,
        dt as dt,
        count(distinct ukey) as exposure_user_cnt,
        count(distinct case when is_pay = 1 then ukey end) as pay_user_cnt,
        sum(ai_amount) as ai_amount
    from user_day_detail
    where is_exposure = 1
    group by
        iver,
        dt
),

cohort_size as (
    select count(1) as cohort_user_cnt
    from full_upgrade_user
)

select
    a.iver as iver,
    s.cohort_user_cnt as cohort_user_cnt,
    count(1) as active_day_cnt,
    round(avg(cast(a.exposure_user_cnt as double)), 1) as avg_exposure_user_cnt_by_day,
    round(avg(cast(a.pay_user_cnt as double)), 2) as avg_pay_user_cnt_by_day,
    round(avg(a.ai_amount), 1) as avg_ai_amount_by_day,
    round(
        avg(
            case when a.exposure_user_cnt > 0
                 then cast(a.pay_user_cnt as double) / a.exposure_user_cnt end
        ) * 100, 4
    ) as avg_pay_rate_by_day_pct,
    round(
        avg(
            case when a.exposure_user_cnt > 0
                 then cast(a.ai_amount as double) / a.exposure_user_cnt end
        ), 4
    ) as avg_amount_per_exposure_by_day
from version_day_agg a
cross join cohort_size s
group by
    a.iver,
    s.cohort_user_cnt
order by
    a.iver
;

-- ============================================================
-- 【附1】先看这批人有多少（跑主查询前建议先跑这个，确认样本量）
--   把上面最后的 select 整段换成下面这段，CTE 不用动：
--
--   select
--       c.version_cnt as 覆盖版本数,
--       c.rollback_day_cnt as 版本回退天数,
--       count(1) as 用户数
--   from user_check c
--   group by
--       c.version_cnt,
--       c.rollback_day_cnt
--   order by
--       c.version_cnt desc,
--       c.rollback_day_cnt,
--       count(1) desc
--   ;
--
-- 【附2】用户 × 版本 宽表（本地做配对检验用，比如配对 t 或 Wilcoxon）
--   同一批人每个人在 8 个版本上的流水，一行一个用户，可直接导出后配对比较。
--   把上面最后的 select 整段换成下面这段，CTE 不用动：
--
--   select
--       ukey,
--       count(distinct case when iver = '13.3.82' and is_exposure = 1 then dt end) as exp_days_13_3_82,
--       sum(case when iver = '13.3.82' then ai_amount else 0 end) as amt_13_3_82,
--       count(distinct case when iver = '13.4.0' and is_exposure = 1 then dt end) as exp_days_13_4_0,
--       sum(case when iver = '13.4.0' then ai_amount else 0 end) as amt_13_4_0,
--       count(distinct case when iver = '13.4.2' and is_exposure = 1 then dt end) as exp_days_13_4_2,
--       sum(case when iver = '13.4.2' then ai_amount else 0 end) as amt_13_4_2,
--       count(distinct case when iver = '13.4.22' and is_exposure = 1 then dt end) as exp_days_13_4_22,
--       sum(case when iver = '13.4.22' then ai_amount else 0 end) as amt_13_4_22,
--       count(distinct case when iver = '13.4.40' and is_exposure = 1 then dt end) as exp_days_13_4_40,
--       sum(case when iver = '13.4.40' then ai_amount else 0 end) as amt_13_4_40,
--       count(distinct case when iver = '13.4.41' and is_exposure = 1 then dt end) as exp_days_13_4_41,
--       sum(case when iver = '13.4.41' then ai_amount else 0 end) as amt_13_4_41,
--       count(distinct case when iver = '13.4.52' and is_exposure = 1 then dt end) as exp_days_13_4_52,
--       sum(case when iver = '13.4.52' then ai_amount else 0 end) as amt_13_4_52,
--       count(distinct case when iver = '13.4.63' and is_exposure = 1 then dt end) as exp_days_13_4_63,
--       sum(case when iver = '13.4.63' then ai_amount else 0 end) as amt_13_4_63
--   from user_day_detail
--   group by
--       ukey
--   ;
--
-- 【附3】放宽样本：如果严格口径人数太少，按需要放开
--   - 只要求 13.4.x 全部升到（允许起点不是 13.3.82）：
--       把 full_upgrade_user 里的条件改成
--       where c.version_cnt = 7 and c.min_version_rank = 2 and c.max_version_rank = 8 and c.rollback_day_cnt = 0
--   - 允许中间跳过个别版本：把 version_cnt = 8 放宽成 >= 6，其余条件不变
--     注意放宽后人群不再完全同质，要单独说明。
-- ============================================================
