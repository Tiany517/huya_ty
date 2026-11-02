with
-- 目标主播名单：蓝鲸上传表，已去重
target_anchor as (
    select distinct
        cast(uid as varchar) as luid
    from zhgametemp.zty_ai_liveroom_uid_list_v1
),

-- 主播日明细：先在独立 CTE 里完成分区时间 + 业务条件过滤（不掺主播名单）
anchor_day_raw as (
    select
        dt,
        cast(ayyuid as varchar) as luid,   -- 【修正】统一 varchar
        nickname,
        live_hours_only_live
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-09-01' and '2026-09-30'   -- 每月改日期
      and live_hours_only_live > 0
),

-- 收敛到目标名单并汇总到「主播 x 日」：join 条件只保留业务关联键 luid
anchor_day as (
    select
        r.dt,
        r.luid,
        max(r.nickname) as nickname,
        sum(r.live_hours_only_live) as live_hours
    from anchor_day_raw r
    inner join target_anchor t
        on r.luid = t.luid
    group by
        r.dt,
        r.luid
),

-- 有效主播：开播天数 >= 5 且 月日均开播时长 > 1h（分母固定 30 = 9月天数，换月一起改）
valid_luid_lst as (
    select distinct
        luid
    from (
        select
            luid,
            nickname,
            count(distinct dt) as live_day_cnt,
            avg(live_hours) as avg_live_hours_by_day,
            avg(live_mins) as avg_live_mins_by_day,
            sum(live_hours) / 30 as avg_live_hours,
            sum(live_mins) / 30 as avg_live_mins
        from (
            select
                a.dt,
                a.luid,
                a.nickname,
                round(a.live_hours, 4) as live_hours,
                round(a.live_hours * 60, 1) as live_mins
            from anchor_day a
        ) t_day
        group by
            luid,
            nickname
    ) t
    where live_day_cnt >= 5
      and avg_live_hours > 1
),

-- 有效日期：有效主播当日观看人数里，剔除观看人数最高的 19 天
valid_date_lst as (
    select distinct
        dt
    from (
        select
            dt,
            user_cnt,
            row_number() over (order by user_cnt desc, dt) as rnk   -- 【修正】加 dt 兜底排序
        from (
            select
                substr(cast(a.dt as varchar), 1, 10) as dt,   -- 【修正】统一成 yyyy-MM-dd
                count(distinct user_ukey) as user_cnt
            from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
            inner join valid_luid_lst b
                on cast(a.luid as varchar) = b.luid   -- 【修正】补 cast
            where a.dt between '2026-09-01' and '2026-09-30'   -- 【修正】'2026-9-30' 补零
              and a.tag = 'gameid'---固定写法
              and a.htime = 'session'---固定写法
              and a.user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios')
            group by
                substr(cast(a.dt as varchar), 1, 10)
        ) t_daily
    ) t_rnk
    where rnk >= 20
)

---【腰部ai直播间 change:有效天数】
,top6h_info as (
    select
        luid,
        gameid,
        game_full_name,
        dt,
        avg(acu_h) as acu,
        max(coalesce(pcu_h, 0)) as pcu
    from (
        select
            luid,
            gameid,
            game_full_name,
            dt,
            h_tag,
            acu_h,
            pcu_h,
            rank() over (partition by luid, gameid, game_full_name, dt order by acu_h desc) as rk
        from (
            select
                cast(ayyuid as varchar) as luid,   -- 【修正】统一 varchar
                gameid,
                dt,
                substr(time_value, 12, 2) as h_tag,
                avg(all_users) as acu_h,
                max(coalesce(all_users, 0)) as pcu_h
            from gamelive.dw_huya_online_users
            where dt between '2026-09-01' and '2026-09-30'   -- 【修正】补上界，每月改日期
              and tag = 'server_ayyuid_gameid_session'        -- gameid 分区
              ---and tag = 'server_ayyuid_liveid_session'    -- liveid 分区
              and cast(ayyuid as varchar) in (select luid from valid_luid_lst)   -- 【修正】补 cast
            group by
                cast(ayyuid as varchar),
                gameid,
                dt,
                substr(time_value, 12, 2)
        ) a
        left join (
            select
                gid,
                game_full_name
            from gamelive.to_main_games_day
            where dt = '2026-09-30'   -- 每月改日期（游戏快照）
            group by
                gid,
                game_full_name
        ) b
            on a.gameid = b.gid
    ) t1
    where rk <= 6
      and game_full_name != '其他直播'
      and pcu_h > 10
    group by
        luid,
        gameid,
        game_full_name,
        dt
)

,dau_info as (
    select
        dt,
        cast(luid as varchar) as luid,   -- 【修正】统一 varchar
        igameid as gameid,
        count(distinct user_ukey) as app_dau,
        sum(user_duration / 60000 / 60) as user_duration   -- 毫秒 -> 小时
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '2026-09-01' and '2026-09-30'   -- 【修正】补上界，每月改日期
      and tag = 'gameid'---固定写法
      and htime = 'session'---固定写法
      and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')   -- app 端
      and cast(luid as varchar) in (select luid from valid_luid_lst)   -- 每次检查更新
    group by
        dt,
        cast(luid as varchar),
        igameid
)

,detail_info as (
    select
        m_tag,
        w_tag,
        a.dt,
        a.luid,
        d.nickname,
        a.game_name,
        a.gameid,
        max_acu as acu_allday,
        max_pcu,
        live_mins,
        b.acu,
        c.app_dau,
        c.user_duration as app_view_mins,
        c.user_duration / c.app_dau as gs_rj
    from (
        select
            date_trunc('month', date(dt)) as m_tag,
            date_trunc('week', date(dt)) as w_tag,
            dt,
            cast(ayyuid as varchar) as luid,   -- 【修正】统一 varchar
            gameid,
            game_name,
            max(coalesce(acu, 0)) as max_acu,
            max(coalesce(pcu, 0)) as max_pcu,
            sum(live_mins) as live_mins   -- 字段名是 mins，单位实际是小时
        from gamelive.dm_huya_ayyuid_detail_day
        where dt between '2026-09-01' and '2026-09-30'   -- 【修正】补上界，每月改日期
          and cast(ayyuid as varchar) in (select luid from valid_luid_lst)   -- 每次检查更新
        group by
            date_trunc('month', date(dt)),
            date_trunc('week', date(dt)),
            dt,
            cast(ayyuid as varchar),
            gameid,
            game_name
    ) a
    left join top6h_info b
        on a.luid = b.luid
       and a.dt = b.dt
       and a.gameid = b.gameid
    left join dau_info c
        on a.luid = c.luid
       and a.dt = c.dt
       and a.gameid = c.gameid
    left join (
        -- 若这张表不存在或 uid 不是主播 uid，改成 gamelive.dim_huya_ayyuid_info（nick / yyid / uid）
        select
            cast(uid as varchar) as uid,
            max(nickname) as nickname
        from gamelive.dim_huya_yyuid_info
        where dt = '2026-09-30'   -- 每次检查更新
        group by
            cast(uid as varchar)
    ) d
        on a.luid = d.uid   -- 【修正】两侧都是 varchar
    where max_pcu > 10
      and game_name != '其他直播'
      and substr(cast(a.dt as varchar), 1, 10) in (select dt from valid_date_lst)   -- 9月有效开播日
    group by
        m_tag,
        w_tag,
        a.dt,
        a.luid,
        d.nickname,
        a.game_name,
        a.gameid,
        max_acu,
        max_pcu,
        live_mins,
        b.acu,
        c.app_dau,
        c.user_duration
)

-- 主查询：主播 x 品类 x 月
select
    m_tag as "月标签"
    , game_name as "品类"
    , luid as "主播uid"
    , nickname as "主播昵称"
    , acu as "日均acu"
    , pcu as "最高pcu"
    , live_mins as "日均直播时长(h)"
    , app_dau as "日均appdau"
    , app_view_mins as "日均观时(h)"
    , gs_rj as "日均人均观时(min)"
    -- , first_yb_m as "首次腰部月份"
    , acu_type as "acu分层"
from (
    select
        m_tag,
        game_name,
        luid,
        nickname,
        acu,
        pcu,
        live_mins,
        app_view_mins,
        app_dau,
        gs_rj,
        min(m_tag) over (partition by game_name, luid) as first_yb_m,
        case
            when acu >= 2000 then '头部'
            when acu >= 1000 then '颈部'
            when acu >= 100 then '腰部'
            else '尾部'
        end as acu_type
    from (
        select
            m_tag,
            game_name,
            luid,
            nickname,
            coalesce(avg(acu), 0) as acu,
            max(max_pcu) as pcu,
            avg(live_mins) as live_mins,
            avg(app_view_mins) as app_view_mins,
            avg(app_dau) as app_dau,
            avg(gs_rj) * 60 as gs_rj
        from detail_info
        group by
            m_tag,
            game_name,
            luid,
            nickname
    ) t
    where acu >= 100
) t1
order by
    m_tag desc,
    game_name desc,
    first_yb_m desc,
    acu desc;