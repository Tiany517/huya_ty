-- 斯诺克各赛事 DAU/观看UV/拉新/回流汇总
-- 生成日期：2026-08-12
-- bigdata 引擎：Spark
-- 成功任务：
--   观看指标 rid = 1207520039022460928
--   拉新回流指标 rid = 1207520262598872064
-- 说明：
--   1. 所有赛事统一使用主播表 zhgametemp.zty_snooker_shanghai_master_2026。
--   2. SQL 未使用 cross join 或 full outer join。
--   3. 本文件保留可复盘口径；本地宽表由两个已下载结果按 match_seq 合并生成。

with luid_list as (
    select distinct
        cast(luid as string) as luid
    from zhgametemp.zty_snooker_shanghai_master_2026
),

luid_cnt as (
    select
        count(distinct luid) as event_luid_cnt
    from luid_list
),

match_info as (
    select 1 as match_seq, '2024上海大师赛' as match_name, '2024-07-15' as start_dt, '2024-07-21' as end_dt union all
    select 2, '2024英国公开赛', '2024-08-30', '2024-09-07' union all
    select 3, '2024武汉公开赛', '2024-09-16', '2024-09-22' union all
    select 4, '2024国际锦标赛', '2024-09-23', '2024-09-29' union all
    select 5, '2024北爱尔兰公开赛', '2024-10-06', '2024-10-12' union all
    select 6, '2024英格兰公开赛', '2024-10-20', '2024-10-27' union all
    select 7, '2024冠中冠', '2024-11-03', '2024-11-10' union all
    select 8, '2024英锦赛', '2024-11-23', '2024-12-01' union all
    select 9, '2024苏格兰公开赛', '2024-12-04', '2024-12-07' union all
    select 10, '2025伦敦大师赛', '2025-01-12', '2025-01-19' union all
    select 11, '2025德国大师赛', '2025-01-27', '2025-02-02' union all
    select 12, '2025威尔士公开赛', '2025-02-10', '2025-02-16' union all
    select 13, '2025球员锦标赛', '2025-02-24', '2025-03-02' union all
    select 14, '2025巡回锦标赛', '2025-03-17', '2025-03-23' union all
    select 15, '2025世锦赛资格赛', '2025-03-31', '2025-04-06' union all
    select 16, '2025斯诺克世锦赛正赛', '2025-04-19', '2025-05-05' union all
    select 17, '2025上海大师赛', '2025-07-28', '2025-08-03' union all
    select 18, '2025欧洲大师赛', '2025-08-24', '2025-08-30' union all
    select 19, '2025英国公开赛', '2025-09-15', '2025-09-21' union all
    select 20, '2025武汉公开赛', '2025-09-22', '2025-09-28' union all
    select 21, '2025北爱尔兰公开赛', '2025-10-07', '2025-10-13' union all
    select 22, '2025英格兰公开赛', '2025-10-19', '2025-10-26' union all
    select 23, '2025冠中冠', '2025-11-02', '2025-11-09' union all
    select 24, '2025英锦赛', '2025-11-29', '2025-12-07' union all
    select 25, '2025苏格兰公开赛', '2025-12-10', '2025-12-13' union all
    select 26, '2025大奖赛', '2025-12-15', '2025-12-21' union all
    select 27, '2026伦敦大师赛', '2026-01-11', '2026-01-18' union all
    select 28, '2026德国大师赛', '2026-01-26', '2026-02-01' union all
    select 29, '2026威尔士公开赛', '2026-02-03', '2026-02-08' union all
    select 30, '2026球员锦标赛', '2026-02-17', '2026-02-22' union all
    select 31, '2026大奖赛', '2026-02-23', '2026-03-01' union all
    select 32, '2026巡回锦标赛', '2026-03-16', '2026-03-22' union all
    select 33, '2026世锦赛资格赛', '2026-03-30', '2026-04-05' union all
    select 34, '2026斯诺克世锦赛正赛', '2026-04-18', '2026-05-06' union all
    select 35, '2026上海大师赛', '2026-07-27', '2026-08-02'
),

daily_view as (
    select
        m.match_seq,
        s.dt,
        count(distinct s.user_ukey) as view_user_cnt
    from match_info m
    inner join gamelive.dwt_huya_ayyuid_session_from_server_with_user s
        on s.dt between m.start_dt and m.end_dt
    inner join luid_list l
        on cast(s.luid as string) = l.luid
    where s.dt between '2024-07-15' and '2026-08-02'
      and s.tag = 'gameid'
      and s.htime = 'session'
      and s.user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
      and s.user_ukey is not null
    group by m.match_seq, s.dt
),

event_view as (
    select
        m.match_seq,
        count(distinct s.user_ukey) as event_view_uv
    from match_info m
    inner join gamelive.dwt_huya_ayyuid_session_from_server_with_user s
        on s.dt between m.start_dt and m.end_dt
    inner join luid_list l
        on cast(s.luid as string) = l.luid
    where s.dt between '2024-07-15' and '2026-08-02'
      and s.tag = 'gameid'
      and s.htime = 'session'
      and s.user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
      and s.user_ukey is not null
    group by m.match_seq
),

view_summary as (
    select
        m.match_seq,
        m.match_name,
        m.start_dt,
        m.end_dt,
        datediff(to_date(m.end_dt), to_date(m.start_dt)) + 1 as observed_day,
        (select event_luid_cnt from luid_cnt) as event_luid_cnt,
        count(distinct d.dt) as view_observed_day,
        sum(d.view_user_cnt) as view_dau_sum,
        sum(d.view_user_cnt) * 1.0000 / (datediff(to_date(m.end_dt), to_date(m.start_dt)) + 1) as avg_view_dau
    from match_info m
    left join daily_view d
        on m.match_seq = d.match_seq
    group by
        m.match_seq,
        m.match_name,
        m.start_dt,
        m.end_dt
)

select
    s.match_seq,
    s.match_name,
    s.start_dt,
    s.end_dt,
    s.observed_day,
    s.event_luid_cnt,
    s.view_observed_day,
    s.view_dau_sum,
    s.avg_view_dau,
    coalesce(v.event_view_uv, 0) as event_view_uv
from view_summary s
left join event_view v
    on s.match_seq = v.match_seq
order by s.match_seq;

-- 查询二：宽口径/窄口径/搜索口径拉新回流指标
with luid_list as (
    select distinct
        cast(luid as string) as luid
    from zhgametemp.zty_snooker_shanghai_master_2026
),

match_info as (
    select 1 as match_seq, '2024上海大师赛' as match_name, '2024-07-15' as start_dt, '2024-07-21' as end_dt union all
    select 2, '2024英国公开赛', '2024-08-30', '2024-09-07' union all
    select 3, '2024武汉公开赛', '2024-09-16', '2024-09-22' union all
    select 4, '2024国际锦标赛', '2024-09-23', '2024-09-29' union all
    select 5, '2024北爱尔兰公开赛', '2024-10-06', '2024-10-12' union all
    select 6, '2024英格兰公开赛', '2024-10-20', '2024-10-27' union all
    select 7, '2024冠中冠', '2024-11-03', '2024-11-10' union all
    select 8, '2024英锦赛', '2024-11-23', '2024-12-01' union all
    select 9, '2024苏格兰公开赛', '2024-12-04', '2024-12-07' union all
    select 10, '2025伦敦大师赛', '2025-01-12', '2025-01-19' union all
    select 11, '2025德国大师赛', '2025-01-27', '2025-02-02' union all
    select 12, '2025威尔士公开赛', '2025-02-10', '2025-02-16' union all
    select 13, '2025球员锦标赛', '2025-02-24', '2025-03-02' union all
    select 14, '2025巡回锦标赛', '2025-03-17', '2025-03-23' union all
    select 15, '2025世锦赛资格赛', '2025-03-31', '2025-04-06' union all
    select 16, '2025斯诺克世锦赛正赛', '2025-04-19', '2025-05-05' union all
    select 17, '2025上海大师赛', '2025-07-28', '2025-08-03' union all
    select 18, '2025欧洲大师赛', '2025-08-24', '2025-08-30' union all
    select 19, '2025英国公开赛', '2025-09-15', '2025-09-21' union all
    select 20, '2025武汉公开赛', '2025-09-22', '2025-09-28' union all
    select 21, '2025北爱尔兰公开赛', '2025-10-07', '2025-10-13' union all
    select 22, '2025英格兰公开赛', '2025-10-19', '2025-10-26' union all
    select 23, '2025冠中冠', '2025-11-02', '2025-11-09' union all
    select 24, '2025英锦赛', '2025-11-29', '2025-12-07' union all
    select 25, '2025苏格兰公开赛', '2025-12-10', '2025-12-13' union all
    select 26, '2025大奖赛', '2025-12-15', '2025-12-21' union all
    select 27, '2026伦敦大师赛', '2026-01-11', '2026-01-18' union all
    select 28, '2026德国大师赛', '2026-01-26', '2026-02-01' union all
    select 29, '2026威尔士公开赛', '2026-02-03', '2026-02-08' union all
    select 30, '2026球员锦标赛', '2026-02-17', '2026-02-22' union all
    select 31, '2026大奖赛', '2026-02-23', '2026-03-01' union all
    select 32, '2026巡回锦标赛', '2026-03-16', '2026-03-22' union all
    select 33, '2026世锦赛资格赛', '2026-03-30', '2026-04-05' union all
    select 34, '2026斯诺克世锦赛正赛', '2026-04-18', '2026-05-06' union all
    select 35, '2026上海大师赛', '2026-07-27', '2026-08-02'
),

user_detail as (
    select m.match_seq, a.dt, '宽口径' as style, '拉新' as user_type, a.user_ukey
    from match_info m
    inner join zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
        on a.dt between m.start_dt and m.end_dt
    inner join luid_list l
        on cast(a.luid as string) = l.luid
    where a.dt between '2024-07-15' and '2026-08-02'
      and a.guiyin_tag <> 'mailiang'

    union all

    select m.match_seq, a.dt, '宽口径' as style, '回流' as user_type, a.user_ukey
    from match_info m
    inner join zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
        on a.dt between m.start_dt and m.end_dt
    inner join luid_list l
        on cast(a.luid as string) = l.luid
    where a.dt between '2024-07-15' and '2026-08-02'

    union all

    select m.match_seq, a.dt, '窄口径' as style, '拉新' as user_type, a.user_ukey
    from match_info m
    inner join zhgametemp.new_user_neirong_laxin_ukey_v2 a
        on a.dt between m.start_dt and m.end_dt
    inner join luid_list l
        on cast(a.luid as string) = l.luid
    where a.dt between '2024-07-15' and '2026-08-02'
      and a.guiyin_tag <> 'mailiang'

    union all

    select m.match_seq, a.dt, '窄口径' as style, '回流' as user_type, a.user_ukey
    from match_info m
    inner join zhgametemp.neirong_huiliu_ukey_v2_ws a
        on a.dt between m.start_dt and m.end_dt
    inner join luid_list l
        on cast(a.luid as string) = l.luid
    where a.dt between '2024-07-15' and '2026-08-02'

    union all

    select m.match_seq, a.dt, '搜索口径' as style, '拉新' as user_type, a.user_ukey
    from match_info m
    inner join zhgametemp.new_user_neirong_laxin_ukey_v2 a
        on a.dt between m.start_dt and m.end_dt
    inner join luid_list l
        on cast(a.luid as string) = l.luid
    where a.dt between '2024-07-15' and '2026-08-02'
      and a.guiyin_tag = 'search'

    union all

    select m.match_seq, a.dt, '搜索口径' as style, '回流' as user_type, a.user_ukey
    from match_info m
    inner join zhgametemp.neirong_huiliu_ukey_v2_ws a
        on a.dt between m.start_dt and m.end_dt
    inner join luid_list l
        on cast(a.luid as string) = l.luid
    where a.dt between '2024-07-15' and '2026-08-02'
      and a.guiyin_tag = 'search'
),

uv_summary as (
    select
        match_seq,
        style,
        count(distinct case when user_type = '拉新' then user_ukey end) as laxin_uv,
        count(distinct case when user_type = '回流' then user_ukey end) as huiliu_uv,
        count(distinct user_ukey) as laxin_huiliu_uv
    from user_detail
    group by match_seq, style
),

daily_summary as (
    select
        match_seq,
        style,
        sum(laxin_user_cnt) as laxin_dau_sum,
        sum(huiliu_user_cnt) as huiliu_dau_sum,
        sum(laxin_huiliu_user_cnt) as laxin_huiliu_dau_sum
    from (
        select
            match_seq,
            style,
            dt,
            count(distinct case when user_type = '拉新' then user_ukey end) as laxin_user_cnt,
            count(distinct case when user_type = '回流' then user_ukey end) as huiliu_user_cnt,
            count(distinct user_ukey) as laxin_huiliu_user_cnt
        from user_detail
        group by match_seq, style, dt
    ) t
    group by match_seq, style
)

select
    u.match_seq,
    u.style,
    u.laxin_uv,
    u.huiliu_uv,
    u.laxin_huiliu_uv,
    d.laxin_dau_sum,
    d.huiliu_dau_sum,
    d.laxin_huiliu_dau_sum
from uv_summary u
inner join daily_summary d
    on u.match_seq = d.match_seq
   and u.style = d.style
order by u.match_seq, u.style;
