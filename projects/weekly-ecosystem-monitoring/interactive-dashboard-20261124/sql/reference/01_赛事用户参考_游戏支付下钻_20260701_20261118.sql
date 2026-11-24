-- 游戏支付用户下钻明细（Spark SQL）
-- 用途：直接输出指定业务维度组合下的支付金额和支付用户数。
-- 最终粒度：天 x 月份 x 赛事期间 x 游戏分组 x game_id x 游戏名称 x 公会 x 主播 x 大R分组 x 赛事用户。
-- 游戏分组：按季度游戏流水排名，TOP10 显示“TOP10游戏”，其余显示“其他游戏”。
-- 游戏名称：TOP10 显示具体游戏名称，非 TOP10 统一显示“其他游戏”；游戏ID保留真实ID。
-- 支付用户数：在最终每个分组行内对支付用户 user_ukey 做非重复计数。
-- 赛事期间：按每个 game_id 独立计算；剔除赛事日均 DAU 最低 1%（向上取整且至少 1 场），
--           剩余赛事日均 DAU 的中位数作为门槛；赛事日 DAU >= 中位数时为赛事期间，含等于。
-- 赛事用户：对支付日 t 和原 game_id，回看 t-90 至 t-1；
--           同一 game_id 下，赛事主播日期关联观时 / 该 game_id 总观时 >= 70% 判为赛事用户。
-- 数据范围：2026-07-01 至 2026-11-18。
-- 用户过滤：仅保留有效 user_ukey；无法归属用户的流水不进入本明细，因此本明细用于用户下钻，不用于完整收入总额对账。

with copyright_match_anchor_day as (
    -- 粒度：dt x game_id x luid x match_id。赛事主播与日期的关联清单。
    select distinct
        substr(cast(src.day as string), 1, 10) as dt,
        cast(src.game_id as string) as game_id,
        cast(src.uid as string) as luid,
        cast(src.match_id as string) as match_id,
        cast(src.match_name as string) as match_name
    from zhgametemp.hss_huya_dim_game_copyright_info_d_a src
    where src.dt = '2026-11-18'
      and substr(cast(src.day as string), 1, 10)
          between '2026-04-02' and '2026-11-18'
      and src.live_type like '%直播%'
      and src.game_id is not null
      and src.uid is not null
      and trim(cast(src.uid as string)) not in ('', '0', '-1')
),

match_anchor_user_day as (
    -- 粒度：dt x game_id x luid。赛事用户判定不区分赛事名称。
    select
        dt,
        game_id,
        luid
    from copyright_match_anchor_day
    group by
        dt,
        game_id,
        luid
),

match_day_dau as (
    -- 粒度：dt x game_id x match_id。每场赛事每日 APP 去重观看 DAU。
    select
        k.dt,
        k.game_id,
        k.match_id,
        max(k.match_name) as match_name,
        count(distinct cast(s.ukey as string)) as daily_dau
    from copyright_match_anchor_day k
    inner join bp.yyzc_dws_with_user_by_gameid_ayyuid_ukey_day s
        on s.dt = k.dt
       and cast(s.gameid as string) = k.game_id
       and cast(s.ayyuid as string) = k.luid
    where s.dt between '2026-07-01' and '2026-11-18'
      and s.is_app = 1
      and s.is_watch > 0
      and s.is_black = 0
    group by
        k.dt,
        k.game_id,
        k.match_id
),

match_avg_dau as (
    -- 粒度：game_id x match_id。每场赛事按自身赛事日计算日均 DAU。
    select
        game_id,
        match_id,
        max(match_name) as match_name,
        avg(cast(daily_dau as double)) as avg_dau
    from match_day_dau
    group by
        game_id,
        match_id
),

match_avg_dau_ranked as (
    -- 粒度：game_id x match_id。按赛事日均 DAU 升序排名。
    select
        game_id,
        match_id,
        match_name,
        avg_dau,
        count(*) over (partition by game_id) as match_cnt,
        row_number() over (
            partition by game_id
            order by avg_dau asc, match_id asc
        ) as low_dau_rank
    from match_avg_dau
),

game_median_dau as (
    -- 粒度：game_id。剔除最低 1% 后，取剩余赛事日均 DAU 中位数。
    select
        game_id,
        percentile_approx(avg_dau, 0.5) as median_dau
    from match_avg_dau_ranked
    where low_dau_rank > greatest(
        cast(ceil(match_cnt * 0.01) as bigint),
        case when match_cnt > 1 then 1 else 0 end
    )
    group by
        game_id
),

match_day_event_status as (
    -- 粒度：dt x game_id x match_id。DAU 大于等于游戏中位数算赛事期间，包含等于。
    select
        d.dt,
        d.game_id,
        d.match_id,
        case
            when m.median_dau is not null
             and cast(d.daily_dau as double) >= m.median_dau
                then 1
            else 0
        end as is_event_period
    from match_day_dau d
    left join game_median_dau m
        on d.game_id = m.game_id
),

game_day_event_status as (
    -- 粒度：dt x game_id。同一天多场赛事时，任一场达到门槛即算赛事期间。
    select
        dt,
        game_id,
        max(is_event_period) as is_event_period
    from match_day_event_status
    group by
        dt,
        game_id
),

revenue_detail as (
    -- 粒度：dt x 支付用户 x 主播 x game_id。仅保留有效用户游戏收入。
    select
        dt,
        substr(dt, 1, 7) as mth,
        date_trunc('quarter', cast(dt as date)) as quarter_start,
        cast(ext['ukey'] as string) as user_ukey,

        case
            when creator_uid is null
              or trim(cast(creator_uid as string)) in ('', '0', '-1')
                then '未知主播'
            else cast(creator_uid as string)
        end as anchor_uid,

        coalesce(nullif(cast(game_id as string), ''), '未知游戏') as game_id,
        sum(cast(user_consume_amount as double)) as consume_amt
    from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i
    where dt between '2026-07-01' and '2026-11-18'
      and cast(user_consume_amount as double) > 0
      and coalesce(is_free_item, 0) = 0
      and ext['ukey'] is not null
      and trim(cast(ext['ukey'] as string)) not in ('', '0', '-1')
      and cast(game_label as string) in ('游戏')
    group by
        dt,
        substr(dt, 1, 7),
        date_trunc('quarter', cast(dt as date)),
        cast(ext['ukey'] as string),
        case
            when creator_uid is null
              or trim(cast(creator_uid as string)) in ('', '0', '-1')
                then '未知主播'
            else cast(creator_uid as string)
        end,
        coalesce(nullif(cast(game_id as string), ''), '未知游戏')
),

revenue_user_game_day as (
    -- 粒度：dt x 支付用户 x game_id。赛事用户判定目标集合。
    select
        dt,
        user_ukey,
        game_id
    from revenue_detail
    group by
        dt,
        user_ukey,
        game_id
),

user_anchor_game_day_watch as (
    -- 粒度：dt x 用户 x game_id x 主播。回看窗口基础观看数据，端类型不限。
    select
        dt,
        cast(user_ukey as string) as user_ukey,
        cast(igameid as string) as game_id,
        cast(luid as string) as luid,
        sum(cast(user_duration as double)) as watch_ms
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '2026-04-02' and '2026-11-17'
      and tag = 'gameid'
      and htime = 'session'
      and user_ukey is not null
      and trim(cast(user_ukey as string)) not in ('', '0', '-1')
      and igameid is not null
      and luid is not null
      and trim(cast(luid as string)) not in ('', '0', '-1')
      and cast(user_duration as double) > 0
    group by
        dt,
        cast(user_ukey as string),
        cast(igameid as string),
        cast(luid as string)
),

user_game_event_watch as (
    -- 粒度：支付日 t x 用户 x game_id。
    -- 分母：同一 game_id 在 t-90 至 t-1 的全部观时。
    -- 分子：其中命中赛事主播日期关联的观时。
    select
        t.dt,
        t.user_ukey,
        t.game_id,
        sum(w.watch_ms) as total_watch_ms,
        sum(
            case
                when m.luid is not null then w.watch_ms
                else 0
            end
        ) as event_watch_ms
    from revenue_user_game_day t
    inner join user_anchor_game_day_watch w
        on t.user_ukey = w.user_ukey
       and t.game_id = w.game_id
       and cast(w.dt as date) between date_add(cast(t.dt as date), -90)
                                and date_add(cast(t.dt as date), -1)
    left join match_anchor_user_day m
        on w.dt = m.dt
       and w.game_id = m.game_id
       and w.luid = m.luid
    group by
        t.dt,
        t.user_ukey,
        t.game_id
),

user_game_event_type as (
    -- 粒度：支付日 t x 用户 x game_id。赛事观时占比 >= 70% 判为赛事用户。
    select
        dt,
        user_ukey,
        game_id,
        case
            when total_watch_ms > 0
             and event_watch_ms * 1.0 / total_watch_ms >= 0.7
                then '赛事用户'
            else '非赛事用户'
        end as user_event_type
    from user_game_event_watch
),

user_month as (
    -- 粒度：月份 x 用户。游戏大R：用户当月全部游戏消费合计 >= 1000。
    select
        mth,
        user_ukey,
        sum(consume_amt) as user_month_consume_amt,
        case
            when sum(consume_amt) >= 1000 then '大R'
            else '非大R'
        end as user_group
    from revenue_detail
    group by
        mth,
        user_ukey
),

anchor_day_info as (
    -- 粒度：dt x 主播。获取公会名称。
    select
        dt,
        cast(ayyuid as string) as anchor_uid,
        max(nullif(trim(cast(nickname as string)), '')) as nickname,
        coalesce(
            nullif(max(nullif(trim(cast(cname as string)), '')), ''),
            '无公会'
        ) as cname
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-07-01' and '2026-11-18'
      and ayyuid is not null
      and trim(cast(ayyuid as string)) not in ('', '0', '-1')
    group by
        dt,
        cast(ayyuid as string)
),

game_info as (
    -- 粒度：game_id。补游戏名称。
    select
        cast(game_id as string) as game_id,
        max(cast(game_name as string)) as game_name
    from gamelive.dim_huya_game_d_a
    where dt = '2026-11-18'
    group by
        cast(game_id as string)
),

game_quarter as (
    -- 粒度：季度 x game_id。按季度游戏总流水计算 TOP10。
    select
        quarter_start,
        game_id,
        sum(consume_amt) as quarter_consume_amt
    from revenue_detail
    group by
        quarter_start,
        game_id
),

game_quarter_rank as (
    -- 粒度：季度 x game_id。每个季度按游戏流水降序排名。
    select
        quarter_start,
        game_id,
        quarter_consume_amt,
        row_number() over (
            partition by quarter_start
            order by quarter_consume_amt desc, game_id asc
        ) as quarter_revenue_rank
    from game_quarter
)

select
    r.dt as `天`,
    r.mth as `月份`,

    case
        when e.is_event_period = 1 then '赛事期间'
        else '非赛事期间'
    end as `赛事期间`,

    case
        when q.quarter_revenue_rank <= 10 then 'TOP10游戏'
        else '其他游戏'
    end as `游戏分组`,

    r.game_id as `游戏ID`,
    case
        when q.quarter_revenue_rank <= 10
            then coalesce(g.game_name, r.game_id, '未知游戏')
        else '其他游戏'
    end as `游戏名称`,
    coalesce(a.cname, '无公会') as `公会名称`,
    r.anchor_uid as `主播ID`,
    coalesce(a.nickname, '未知主播') as `主播昵称`,

    coalesce(ut.user_event_type, '非赛事用户') as `是否赛事用户`,
    u.user_group as `是否大R`,
    count(distinct r.user_ukey) as `支付用户数`,
    round(sum(r.consume_amt), 2) as `支付金额`

from revenue_detail r

left join anchor_day_info a
    on r.dt = a.dt
   and r.anchor_uid = a.anchor_uid

left join game_info g
    on r.game_id = g.game_id

inner join game_quarter_rank q
    on r.quarter_start = q.quarter_start
   and r.game_id = q.game_id

left join game_day_event_status e
    on r.dt = e.dt
   and r.game_id = e.game_id

left join user_game_event_type ut
    on r.dt = ut.dt
   and r.user_ukey = ut.user_ukey
   and r.game_id = ut.game_id

inner join user_month u
    on r.mth = u.mth
   and r.user_ukey = u.user_ukey

group by
    r.dt,
    r.mth,
    coalesce(a.cname, '无公会'),
    r.anchor_uid,
    coalesce(a.nickname, '未知主播'),
    case
        when q.quarter_revenue_rank <= 10 then 'TOP10游戏'
        else '其他游戏'
    end,
    r.game_id,
    case
        when q.quarter_revenue_rank <= 10
            then coalesce(g.game_name, r.game_id, '未知游戏')
        else '其他游戏'
    end,
    u.user_group,
    case
        when e.is_event_period = 1 then '赛事期间'
        else '非赛事期间'
    end,
    coalesce(ut.user_event_type, '非赛事用户')

order by
    `天`,
    `月份`,
    `赛事期间`,
    `游戏分组`,
    `游戏ID`,
    `游戏名称`,
    `公会名称`,
    `主播ID`,
    `主播昵称`,
    `是否赛事用户`,
    `是否大R`;
