with dashang_agg as (
    select
        a.game_id,
        a.game_name,
        a.creator_uid,
        b.nickname,
        sum(a.user_consume_amount) as total_consume_amt,
        count(distinct a.ext['ukey']) as pay_users_cnt
    from gamelive.dws_huya_revenue_detail_d_i a
    left join (
        select
            uid,
            max(nick) as nickname
        from gamelive.dim_huya_ayyuid_info
        where dt >= '2024-01-01'
        group by uid
    ) b
      on a.creator_uid = b.uid
    where 
        a.dt between '2026-06-22' and '2026-07-05' 
        -- a.dt between '2026-06-01' and '2026-06-30' -- 6月份整体
        and a.user_consume_amount > 0
        and a.game_id in (
            1964, -- 主机游戏
            1732, -- 我的世界
            1997, -- 方舟
            393, -- 炉石传说
            7 -- Dota2
        ) 
    group by 
        a.game_id,
        a.game_name,
        a.creator_uid,
        b.nickname
)



select
    game_id,
    game_name,
    creator_uid,
    nickname,
    total_consume_amt,
    pay_users_cnt,
    rnk,
    total_consume_amt/pay_users_cnt as avg_user_consume_amt
from (
    select
        game_id,
        game_name,
        creator_uid,
        nickname,
        total_consume_amt,
        pay_users_cnt,
        row_number() over (partition by game_id order by total_consume_amt desc) as rnk
    from dashang_agg
)
where rnk <= 20
order by game_id, rnk desc