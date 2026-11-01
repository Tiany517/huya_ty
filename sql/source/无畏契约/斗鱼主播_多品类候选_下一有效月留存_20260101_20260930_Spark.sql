-- 目的：为多品类互动候选补算“下一有效月弹幕用户留存”。
-- 数据源：gamelive.dm_mkt_rowner_day、gamelive.dwt_jingpin_danmulog_day。
-- 时间范围：2026-01-01 至 2026-09-30；不使用尚未结束的 2026-10。
-- 取数范围：51 个含候选的品类，覆盖 547 个“品类 x 斗鱼主播”候选组合；下载后本地仅保留候选组合。
-- 下一有效月：同一品类、同一主播之后第一个有效 ACU 天数 >= 3 的完整月份。
-- 留存：当前月普通弹幕 msgtype='0' 去重发送用户中，下一有效月仍向同品类、同主播发送普通弹幕的用户占比。
-- 留存只作为候选解释指标，不参与候选入选门槛。
-- 有效 ACU 日：ext['vaild_acu'] > 0；ACU 和弹幕人数均基于同一批日期。
-- 引擎：Spark SQL。

with candidate_categories as (
    select 'Apex英雄' as r_category
    union all
    select 'CS2' as r_category
    union all
    select 'DOTA1' as r_category
    union all
    select 'DOTA2' as r_category
    union all
    select 'QQ飞车手游' as r_category
    union all
    select 'lol云顶之弈' as r_category
    union all
    select '一起玩' as r_category
    union all
    select '一起看' as r_category
    union all
    select '三角洲行动' as r_category
    union all
    select '主机' as r_category
    union all
    select '二次元' as r_category
    union all
    select '亿万僵尸' as r_category
    union all
    select '传奇' as r_category
    union all
    select '传奇聚合' as r_category
    union all
    select '冒险岛' as r_category
    union all
    select '刀塔自走棋' as r_category
    union all
    select '剑网3' as r_category
    union all
    select '原神' as r_category
    union all
    select '和平精英' as r_category
    union all
    select '地下城与勇士' as r_category
    union all
    select '天天象棋' as r_category
    union all
    select '太空鹅鸭杀' as r_category
    union all
    select '失控进化-RUST' as r_category
    union all
    select '守望先锋归来' as r_category
    union all
    select '户外' as r_category
    union all
    select '掌心全民麻将' as r_category
    union all
    select '无畏契约' as r_category
    union all
    select '无畏契约：源能行动' as r_category
    union all
    select '明日方舟：终末地' as r_category
    union all
    select '星秀' as r_category
    union all
    select '星秀+颜值' as r_category
    union all
    select '星际争霸' as r_category
    union all
    select '暴雪' as r_category
    union all
    select '格斗游戏' as r_category
    union all
    select '欢乐麻将' as r_category
    union all
    select '派对' as r_category
    union all
    select '火影忍者手游' as r_category
    union all
    select '炉石传说' as r_category
    union all
    select '狼人杀' as r_category
    union all
    select '王者荣耀' as r_category
    union all
    select '穿越火线' as r_category
    union all
    select '竞拍之王' as r_category
    union all
    select '第五人格' as r_category
    union all
    select '绝地求生' as r_category
    union all
    select '英雄联盟' as r_category
    union all
    select '足球游戏' as r_category
    union all
    select '金铲铲之战' as r_category
    union all
    select '雀魂麻将' as r_category
    union all
    select '魔兽世界' as r_category
    union all
    select '魔兽争霸3' as r_category
    union all
    select '魔兽怀旧服' as r_category
),

douyu_anchor_day as (
    select
        cast(a.dt as string) as dt,
        cast(a.r_lid as string) as anchor_id,
        trim(cast(a.r_category as string)) as r_category,
        max(cast(a.r_owner as string)) as r_owner,
        max(coalesce(cast(element_at(a.ext, 'vaild_acu') as double), 0.0)) as valid_acu,
        max(coalesce(cast(a.danmu_ucnt as double), 0.0)) as danmu_ucnt,
        max(coalesce(cast(a.danmu_cnt as double), 0.0)) as danmu_cnt
    from gamelive.dm_mkt_rowner_day a
    inner join candidate_categories p
        on trim(cast(a.r_category as string)) = p.r_category
    where a.dt between '2026-01-01' and '2026-09-30'
      and a.pcode = 'douyu'
    group by
        cast(a.dt as string),
        cast(a.r_lid as string),
        trim(cast(a.r_category as string))
),

anchor_month_base as (
    select
        substr(dt, 1, 7) as month_key,
        r_category,
        anchor_id,
        max_by(r_owner, dt) as anchor_name,
        count(distinct dt) as observed_days,
        count(distinct if(valid_acu > 0, dt, null)) as valid_acu_days,
        avg(if(valid_acu > 0, valid_acu, null)) as avg_daily_acu,
        avg(if(valid_acu > 0, danmu_ucnt, null)) as avg_daily_danmu_users,
        sum(if(valid_acu > 0, danmu_cnt, 0.0)) as total_danmu_cnt
    from douyu_anchor_day
    group by
        substr(dt, 1, 7),
        r_category,
        anchor_id
    having count(distinct if(valid_acu > 0, dt, null)) > 0
),

anchor_month as (
    select
        *,
        cast(
            months_between(
                cast(concat(month_key, '-01') as date),
                date '2020-01-01'
            ) as int
        ) as month_index
    from anchor_month_base
),

anchor_month_next as (
    select
        *,
        first_value(
            if(valid_acu_days >= 3, month_key, null),
            true
        ) over (
            partition by r_category, anchor_id
            order by month_index
            rows between 1 following and unbounded following
        ) as next_valid_month_key,
        first_value(
            if(valid_acu_days >= 3, month_index, null),
            true
        ) over (
            partition by r_category, anchor_id
            order by month_index
            rows between 1 following and unbounded following
        ) as next_valid_month_index,
        first_value(
            if(valid_acu_days >= 3, valid_acu_days, null),
            true
        ) over (
            partition by r_category, anchor_id
            order by month_index
            rows between 1 following and unbounded following
        ) as next_valid_acu_days
    from anchor_month
),

-- 只提取候选品类和主播的普通弹幕用户，先压缩到主播-品类-日-用户。
danmu_user_day_raw as (
    select
        cast(a.dt as string) as dt,
        cast(a.uid as string) as anchor_id,
        trim(cast(a.r_category as string)) as r_category,
        cast(a.sender as string) as danmu_user_id
    from gamelive.dwt_jingpin_danmulog_day a
    inner join candidate_categories p
        on trim(cast(a.r_category as string)) = p.r_category
    where a.dt between '2026-01-01' and '2026-09-30'
      and a.pcode = 'douyu'
      and cast(a.msgtype as string) = '0'
      and a.sender is not null
      and trim(cast(a.sender as string)) <> ''
    group by
        cast(a.dt as string),
        cast(a.uid as string),
        trim(cast(a.r_category as string)),
        cast(a.sender as string)
),

-- 留存只使用存在有效 ACU 的主播日，确保互动与留存样本口径一致。
danmu_user_day as (
    select
        d.dt,
        d.r_category,
        d.anchor_id,
        u.danmu_user_id
    from danmu_user_day_raw u
    inner join douyu_anchor_day d
        on u.dt = d.dt
       and u.r_category = d.r_category
       and u.anchor_id = d.anchor_id
    where d.valid_acu > 0
),

monthly_user as (
    select
        substr(dt, 1, 7) as month_key,
        r_category,
        anchor_id,
        danmu_user_id
    from danmu_user_day
    group by
        substr(dt, 1, 7),
        r_category,
        anchor_id,
        danmu_user_id
),

retention_user_flag as (
    select
        a.month_key as current_month_key,
        a.r_category,
        a.anchor_id,
        a.next_valid_month_key,
        a.next_valid_month_index - a.month_index as retention_gap_months,
        c.danmu_user_id,
        if(n.danmu_user_id is not null, 1, 0) as is_retained
    from anchor_month_next a
    left join monthly_user c
        on a.month_key = c.month_key
       and a.r_category = c.r_category
       and a.anchor_id = c.anchor_id
    left join monthly_user n
        on a.r_category = n.r_category
       and a.anchor_id = n.anchor_id
       and a.next_valid_month_key = n.month_key
       and c.danmu_user_id = n.danmu_user_id
),

retention_metric as (
    select
        current_month_key as month_key,
        r_category,
        anchor_id,
        count(distinct danmu_user_id) as retention_base_users,
        sum(is_retained) as next_valid_month_retained_users
    from retention_user_flag
    group by
        current_month_key,
        r_category,
        anchor_id
)

select
    a.month_key as `月份`,
    a.r_category as `品类`,
    a.anchor_id as `斗鱼主播ID`,
    a.anchor_name as `主播名称`,
    a.valid_acu_days as `有效ACU天数`,
    round(a.avg_daily_acu, 2) as `月日均ACU`,
    round(a.avg_daily_danmu_users, 2) as `月日均弹幕人数`,
    a.next_valid_month_key as `下一有效月`,
    a.next_valid_month_index - a.month_index as `留存间隔月数`,
    a.next_valid_acu_days as `下一有效月有效ACU天数`,
    coalesce(r.retention_base_users, 0) as `当前月留存分母用户数`,
    coalesce(r.next_valid_month_retained_users, 0) as `下一有效月观察留存用户数`,
    case
        when a.next_valid_month_key is null then null
        when coalesce(r.retention_base_users, 0) <= 0 then null
        else round(
            1.0 * r.next_valid_month_retained_users
            / r.retention_base_users,
            4
        )
    end as `下一有效月留存率`,
    case
        when a.next_valid_month_key is not null
         and coalesce(r.retention_base_users, 0) >= 30 then '高样本'
        when a.next_valid_month_key is not null
         and coalesce(r.retention_base_users, 0) >= 20 then '中样本'
        else '低样本'
    end as `留存样本等级`,
    case
        when a.next_valid_month_key is null then null
        when a.next_valid_month_index - a.month_index = 1 then 1
        else 0
    end as `是否自然次月`
from anchor_month_next a
left join retention_metric r
    on a.month_key = r.month_key
   and a.r_category = r.r_category
   and a.anchor_id = r.anchor_id
order by
    a.r_category,
    a.anchor_id,
    a.month_key;
