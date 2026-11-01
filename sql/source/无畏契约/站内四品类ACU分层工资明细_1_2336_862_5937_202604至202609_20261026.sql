-- 目的：计算主品类属于英雄联盟、王者荣耀、CS、无畏契约的站内主播，
--       在2026-04至2026-09期间的ACU分层及正工资月份明细。
-- 扩展品类：1（英雄联盟）、2336（王者荣耀）、862（CS）、5937（无畏契约）。
-- 有效开播日：当天所选品类 live_mins（小时）合计 × 60 >= 15分钟。
-- 近6月ACU：全部有效开播日 ACU 直接平均，每个有效日等权。
-- 工资：2026-04至2026-09，同一主播同月 final_amount 汇总；仅限定 role='主播'。
-- 输出粒度：ACU分层 × 站内主播 × 月份。

with anchor_day as (
    -- 四品类主播日粒度；live_mins 单位为小时，乘以60换算为分钟
    select
        cast(dt as varchar) as dt,
        cast(ayyuid as varchar) as luid,
        max(cast(nickname as varchar)) as nickname,
        coalesce(avg(cast(acu as double)), 0.0) as day_acu
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-04-01' and '2026-09-30'
      and cast(gameid as varchar) in ('1', '2336', '862', '5937')
    group by
        cast(dt as varchar),
        cast(ayyuid as varchar)
    having sum(
        coalesce(cast(live_mins as double), 0.0)
    ) * 60 >= 15
),

anchor_month as (
    -- 主播月粒度：该月有效开播日的日均ACU
    select
        substr(dt, 1, 7) as mth,
        luid,
        max(nickname) as nickname,
        avg(day_acu) as monthly_avg_acu
    from anchor_day
    group by
        substr(dt, 1, 7),
        luid
),

anchor_acu as (
    -- 近6月ACU：
    -- 对2026-04至2026-09全部有效开播日的ACU直接求平均，每个有效日等权
    select
        luid,
        max(nickname) as nickname,
        count(distinct dt) as valid_days,
        count(distinct substr(dt, 1, 7)) as active_months,
        avg(day_acu) as near6_acu
    from anchor_day
    group by luid
),

game_score as (
    -- 按主播 × 品类累计观众观看时长，用于判断主播主品类
    select
        cast(s.luid as varchar) as luid,
        cast(s.igameid as varchar) as game_id,
        sum(
            coalesce(cast(s.user_duration as double), 0.0)
        ) as total_watch_ms
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user s
    inner join anchor_acu a
        on cast(s.luid as varchar) = a.luid
    where s.dt between '2026-01-01' and '2026-10-21'
      and s.tag = 'gameid'
      and s.htime = 'session'
      and s.user_product in (
          'huya_andriod',
          'huya_ipad',
          'huya_pad',
          'huya_ios'
      )
      and s.luid is not null
      and s.igameid is not null
      and s.user_ukey is not null
      and coalesce(cast(s.user_duration as double), 0.0) > 0
    group by
        cast(s.luid as varchar),
        cast(s.igameid as varchar)
),

main_game as (
    -- 每个主播累计观看时长最高的品类；并列时取game_id较小者
    -- 仅保留主品类属于英雄联盟、王者荣耀、CS、无畏契约的主播
    select
        luid,
        game_id as main_game_id
    from (
        select
            luid,
            game_id,
            row_number() over (
                partition by luid
                order by total_watch_ms desc, game_id
            ) as rn
        from game_score
    ) t
    where rn = 1
      and game_id in ('1', '2336', '862', '5937')
),

anchor_benchmark as (
    select
        a.luid,
        a.nickname,
        a.valid_days,
        a.active_months,
        a.near6_acu,
        g.main_game_id,
        case
            when a.near6_acu is null then null
            when a.near6_acu < 100 then 0
            when a.near6_acu < 200 then 100
            when a.near6_acu < 300 then 200
            when a.near6_acu < 400 then 300
            when a.near6_acu < 500 then 400
            when a.near6_acu < 600 then 500
            when a.near6_acu < 700 then 600
            when a.near6_acu < 800 then 700
            when a.near6_acu < 900 then 800
            when a.near6_acu < 1000 then 900
            when a.near6_acu < 1100 then 1000
            when a.near6_acu < 1200 then 1100
            when a.near6_acu < 1300 then 1200
            when a.near6_acu < 1400 then 1300
            when a.near6_acu < 1500 then 1400
            when a.near6_acu < 1600 then 1500
            when a.near6_acu < 1700 then 1600
            when a.near6_acu < 1800 then 1700
            when a.near6_acu < 1900 then 1800
            when a.near6_acu < 2000 then 1900
            when a.near6_acu < 2100 then 2000
            when a.near6_acu < 2200 then 2100
            when a.near6_acu < 2300 then 2200
            when a.near6_acu < 2400 then 2300
            when a.near6_acu < 2500 then 2400
            when a.near6_acu < 2600 then 2500
            when a.near6_acu < 2700 then 2600
            when a.near6_acu < 2800 then 2700
            when a.near6_acu < 2900 then 2800
            when a.near6_acu < 3000 then 2900
            when a.near6_acu < 3100 then 3000
            when a.near6_acu < 3200 then 3100
            when a.near6_acu < 3300 then 3200
            when a.near6_acu < 3400 then 3300
            when a.near6_acu < 3500 then 3400
            when a.near6_acu < 3600 then 3500
            when a.near6_acu < 3700 then 3600
            when a.near6_acu < 3800 then 3700
            when a.near6_acu < 3900 then 3800
            when a.near6_acu < 4000 then 3900
            else 4000
        end as tier_lower
    from anchor_acu a
    inner join main_game g
        on a.luid = g.luid
),

salary_monthly as (
    -- 站内主播月工资：
    -- 同一主播同月多条final_amount先汇总；
    -- 按要求只限制role='主播'，不限制game_name。
    select
        substr(cast(settlement_date as varchar), 1, 7) as mth,
        cast(uid as varchar) as uid,
        max(cast(anchor_nickname as varchar)) as anchor_nickname,
        sum(
            coalesce(final_amount, cast(0 as decimal(18,2)))
        ) as salary_amount,
        count(*) as salary_record_cnt
    from bp.md_dwd_anchor_salary
    where settlement_date >= '2026-04-01'
      and settlement_date < '2026-10-01'
      and cast(role as varchar) = '主播'
    group by
        substr(cast(settlement_date as varchar), 1, 7),
        cast(uid as varchar)
),

month_grid(mth, month_no) as (
    -- 保证每个主播都有2026-04至2026-09六行
    values
        ('2026-04', 1),
        ('2026-05', 2),
        ('2026-06', 3),
        ('2026-07', 4),
        ('2026-08', 5),
        ('2026-09', 6)
),

-- 明细粒度：ACU分层 × 站内主播 × 月份
internal_anchor_month_salary as (
    select
        b.tier_lower,
        b.luid,
        b.nickname,
        b.main_game_id,
        b.valid_days,
        b.active_months,
        b.near6_acu,
        m.monthly_avg_acu,
        g.mth,
        g.month_no,
        s.salary_amount,
        coalesce(s.salary_record_cnt, 0) as salary_record_cnt,
        case
            when coalesce(s.salary_record_cnt, 0) = 0 then '无结算记录'
            when s.salary_amount > 0 then '有发薪'
            else '零或负发薪'
        end as salary_status
    from anchor_benchmark b

    -- 每个站内主播补齐固定六个月
    cross join month_grid g

    left join salary_monthly s
        on b.luid = s.uid
       and g.mth = s.mth

    -- 补充主播当月有效开播日日均ACU
    left join anchor_month m
        on b.luid = m.luid
       and g.mth = m.mth

    where b.tier_lower is not null
)

select
    case
        when tier_lower = 4000 then '4000及以上'
        else concat(
            cast(tier_lower as varchar),
            '-<',
            cast(tier_lower + 100 as varchar)
        )
    end as "近6月日均ACU分层",

    tier_lower as "ACU分层下限",
    luid as "站内主播UID",
    nickname as "站内主播昵称",
    main_game_id as "主品类ID",
    valid_days as "近6月有效开播天数",
    active_months as "近6月有效月份数",

    cast(
        round(near6_acu, 2)
        as decimal(38,2)
    ) as "近6月有效日日均ACU",

    mth as "结算月份",

    cast(
        round(monthly_avg_acu, 2)
        as decimal(38,2)
    ) as "当月有效日日均ACU",

    cast(
        round(salary_amount, 2)
        as decimal(38,2)
    ) as "当月工资",

    salary_record_cnt as "当月薪资记录数",
    salary_status as "当月发薪状态"

from internal_anchor_month_salary
order by
    tier_lower,
    near6_acu desc,
    luid,
    month_no;
