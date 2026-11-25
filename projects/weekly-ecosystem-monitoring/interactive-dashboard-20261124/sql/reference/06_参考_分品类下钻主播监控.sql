with game_labeled as (
    select distinct
        cast(gid as string) as gameid,
        game_full_name as game_name
    from gamelive.to_main_games_day
    where dt = '2026-08-23'
      and game_full_name = '英雄联盟' --改这里
),

anchor_name as (
    select
        cast(luid as string) as luid,
        substring_index(max(snick), ',', 1) as snick
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '2026-03-01' and '2026-08-23'
      and luid is not null
      and snick is not null
    group by
        cast(luid as string)
),

anchor_live_daily as (
    select
        a.dt,
        cast(a.ayyuid as string) as luid,
        g.game_name,
        case
            when sum(coalesce(a.live_mins, 0)) > 0
                then '是'
            else '否'
        end as is_live,
        sum(coalesce(a.live_mins, 0)) as live_mins,
        coalesce(avg(a.acu), 0) as avg_acu
    from gamelive.dm_huya_ayyuid_detail_day a
    inner join game_labeled g
        on cast(a.gameid as string) = g.gameid
    where a.dt between '2026-03-01' and '2026-08-23'
    group by
        a.dt,
        cast(a.ayyuid as string),
        g.game_name
),

session_user_daily as (
    select
        s.dt,
        cast(s.luid as string) as luid,
        cast(s.user_ukey as string) as user_ukey,
        g.game_name,
        sum(coalesce(s.user_duration, 0)) as user_duration
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user s
    inner join game_labeled g
        on cast(s.igameid as string) = g.gameid
    where s.dt between '2026-03-01' and '2026-08-23'
      and s.tag = 'gameid'
      and s.htime = 'session'
      and s.user_product in (
          'huya_andriod',
          'huya_ipad',
          'huya_pad',
          'huya_ios',
          'hmos_kiwi'
      )
      and s.user_ukey is not null
      and s.luid is not null
    group by
        s.dt,
        cast(s.luid as string),
        cast(s.user_ukey as string),
        g.game_name
),

anchor_dau_daily as (
    select
        dt,
        game_name,
        luid,
        count(distinct user_ukey) as daily_dau,
        sum(user_duration) as total_user_duration
    from session_user_daily
    group by
        dt,
        game_name,
        luid
),

category_dau_daily as (
    select
        dt,
        game_name,
        count(distinct user_ukey) as daily_dau,
        sum(user_duration) as total_user_duration
    from session_user_daily
    group by
        dt,
        game_name
),

anchor_revenue_daily as (
    select
        r.dt,
        coalesce(cast(r.creator_uid as string), '__UNATTRIBUTED__') as luid,
        g.game_name,
        sum(r.user_consume_amount) as daily_revenue,
        count(distinct cast(r.ext['ukey'] as string))
            as daily_pay_user_cnt
    from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i r
    inner join game_labeled g
        on cast(r.game_id as string) = g.gameid
    where r.dt between '2026-03-01' and '2026-08-23'
      and r.user_consume_amount > 0
      and r.ext['ukey'] is not null
    group by
        r.dt,
        coalesce(cast(r.creator_uid as string), '__UNATTRIBUTED__'),
        g.game_name
),

category_revenue_daily as (
    select
        r.dt,
        g.game_name,
        sum(r.user_consume_amount) as daily_revenue,
        count(distinct cast(r.ext['ukey'] as string))
            as daily_pay_user_cnt
    from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i r
    inner join game_labeled g
        on cast(r.game_id as string) = g.gameid
    where r.dt between '2026-03-01' and '2026-08-23'
      and r.user_consume_amount > 0
      and r.ext['ukey'] is not null
    group by
        r.dt,
        g.game_name
),

attribution_user_daily as (
    select distinct
        a.dt,
        cast(a.luid as string) as luid,
        cast(a.ukey as string) as user_ukey,
        g.game_name
    from zhgametemp.cwq_huya_ukey_shichang_luid_gameid_guishu_day_v1 a
    inner join game_labeled g
        on cast(a.igameid as string) = g.gameid
    where a.dt between '2026-03-01' and '2026-08-23'
      and a.ukey is not null
      and a.luid is not null
),

anchor_attribution_daily as (
    select
        dt,
        game_name,
        luid,
        count(distinct user_ukey)
            as daily_attribution_user_cnt
    from attribution_user_daily
    group by
        dt,
        game_name,
        luid
),

category_attribution_daily as (
    select
        dt,
        game_name,
        count(distinct user_ukey)
            as daily_attribution_user_cnt
    from attribution_user_daily
    group by
        dt,
        game_name
),

interest_anchor_daily as (
    select
        i.dt,
        coalesce(cast(i.luid as string), '__UNATTRIBUTED__') as luid,
        g.game_name,
        sum(i.user_pro) as interest_user_cnt,
        sum(
            case
                when cast(i.gameid as string) <> '1'
                    then i.user_pro
                else 0
            end
        ) as non_lol_interest_user_cnt
    from zhgametemp.cwq_huya_7days_xqzs_detail_tmp i
    inner join game_labeled g
        on cast(i.gameid as string) = g.gameid
    where i.dt between '2026-03-01' and '2026-08-23'
    group by
        i.dt,
        cast(i.luid as string),
        g.game_name
),

interest_category_daily as (
    select
        i.dt,
        g.game_name,
        sum(i.user_pro) as interest_user_cnt,
        sum(
            case
                when cast(i.gameid as string) <> '1'
                    then i.user_pro
                else 0
            end
        ) as non_lol_interest_user_cnt
    from zhgametemp.cwq_huya_7days_xqzs_detail_tmp i
    inner join game_labeled g
        on cast(i.gameid as string) = g.gameid
    where i.dt between '2026-03-01' and '2026-08-23'
    group by
        i.dt,
        g.game_name
),

unmatched_revenue_daily as (
    select
        r.dt,
        r.game_name,
        sum(r.daily_revenue) as daily_revenue,
        sum(r.daily_pay_user_cnt) as daily_pay_user_cnt
    from anchor_revenue_daily r
    left join anchor_live_daily l
        on r.dt = l.dt
       and r.game_name = l.game_name
       and r.luid = l.luid
    where l.luid is null
    group by
        r.dt,
        r.game_name
),

unmatched_attribution_daily as (
    select
        a.dt,
        a.game_name,
        sum(a.daily_attribution_user_cnt) as daily_attribution_user_cnt
    from anchor_attribution_daily a
    left join anchor_live_daily l
        on a.dt = l.dt
       and a.game_name = l.game_name
       and a.luid = l.luid
    where l.luid is null
    group by
        a.dt,
        a.game_name
),

unmatched_interest_daily as (
    select
        i.dt,
        i.game_name,
        sum(i.interest_user_cnt) as interest_user_cnt,
        sum(i.non_lol_interest_user_cnt) as non_lol_interest_user_cnt
    from interest_anchor_daily i
    left join anchor_live_daily l
        on i.dt = l.dt
       and i.game_name = l.game_name
       and i.luid = l.luid
    where l.luid is null
    group by
        i.dt,
        i.game_name
),

unmatched_keys_daily as (
    select dt, game_name from unmatched_revenue_daily
    union
    select dt, game_name from unmatched_attribution_daily
    union
    select dt, game_name from unmatched_interest_daily
),

category_keys_daily as (
    select distinct
        dt,
        game_name
    from category_dau_daily
),

result as (

    -- 主播明细
    select
        l.dt as `日期`,
        l.game_name as `品类`,
        l.luid as `主播uid`,
        coalesce(n.snick, '') as `主播昵称`,

        coalesce(l.is_live, '否') as `当天是否开播`,
        coalesce(l.live_mins, 0) as `开播时长_小时`,
        coalesce(l.avg_acu, 0) as `当天平均acu`,

        coalesce(d.daily_dau, 0) as `dau`,

        coalesce(r.daily_revenue, 0) as `打赏流水`,

        coalesce(r.daily_pay_user_cnt, 0) as `打赏人数`,

        coalesce(r.daily_revenue, 0)
            / nullif(r.daily_pay_user_cnt, 0)
            as `人均打赏流水`,

        coalesce(d.total_user_duration, 0) / 1000.0 / 60
            / nullif(d.daily_dau, 0)
            as `人均观时_分钟`,

        coalesce(a.daily_attribution_user_cnt, 0)
            as `归因人数`,

        coalesce(i.interest_user_cnt, 0)
            as `兴趣用户数`,

        coalesce(i.non_lol_interest_user_cnt, 0)
            as `非lol兴趣用户数`,

        '主播明细' as `数据粒度`

    from anchor_live_daily l
    left join anchor_dau_daily d
        on l.dt = d.dt
       and l.game_name = d.game_name
       and l.luid = d.luid
    left join anchor_revenue_daily r
        on l.dt = r.dt
       and l.game_name = r.game_name
       and l.luid = r.luid
    left join anchor_attribution_daily a
        on l.dt = a.dt
       and l.game_name = a.game_name
       and l.luid = a.luid
    left join interest_anchor_daily i
        on l.dt = i.dt
       and l.game_name = i.game_name
       and l.luid = i.luid
    left join anchor_name n
        on l.luid = n.luid

    union all

    -- 未出现在开播主播明细中的指标，按日期汇总为一个补充行。
    select
        u.dt as `日期`,
        u.game_name as `品类`,
        '__UNATTRIBUTED__' as `主播uid`,
        '未归属主播' as `主播昵称`,
        '否' as `当天是否开播`,
        cast(0 as double) as `开播时长_小时`,
        cast(0 as double) as `当天平均acu`,
        cast(0 as bigint) as `dau`,
        coalesce(r.daily_revenue, 0) as `打赏流水`,
        coalesce(r.daily_pay_user_cnt, 0) as `打赏人数`,
        coalesce(r.daily_revenue, 0)
            / nullif(r.daily_pay_user_cnt, 0)
            as `人均打赏流水`,
        cast(null as double) as `人均观时_分钟`,
        coalesce(a.daily_attribution_user_cnt, 0) as `归因人数`,
        coalesce(i.interest_user_cnt, 0) as `兴趣用户数`,
        coalesce(i.non_lol_interest_user_cnt, 0) as `非lol兴趣用户数`,
        '主播明细' as `数据粒度`
    from unmatched_keys_daily u
    left join unmatched_revenue_daily r
        on u.dt = r.dt
       and u.game_name = r.game_name
    left join unmatched_attribution_daily a
        on u.dt = a.dt
       and u.game_name = a.game_name
    left join unmatched_interest_daily i
        on u.dt = i.dt
       and u.game_name = i.game_name

    union all

    -- 品类整体
    select
        d0.dt as `日期`,
        d0.game_name as `品类`,
        cast(null as string) as `主播uid`,
        '品类整体' as `主播昵称`,

        cast(null as string) as `当天是否开播`,
        cast(null as double) as `开播时长_小时`,
        cast(null as double) as `当天平均acu`,

        d.daily_dau as `dau`,

        coalesce(r.daily_revenue, 0) as `打赏流水`,

        coalesce(r.daily_pay_user_cnt, 0) as `打赏人数`,

        coalesce(r.daily_revenue, 0)
            / nullif(r.daily_pay_user_cnt, 0)
            as `人均打赏流水`,

        d.total_user_duration / 1000.0 / 60
            / nullif(d.daily_dau, 0)
            as `人均观时_分钟`,

        coalesce(a.daily_attribution_user_cnt, 0)
            as `归因人数`,

        coalesce(i.interest_user_cnt, 0)
            as `兴趣用户数`,

        coalesce(i.non_lol_interest_user_cnt, 0)
            as `非lol兴趣用户数`,

        '品类整体' as `数据粒度`

    from category_keys_daily d0
    left join category_dau_daily d
        on d0.dt = d.dt
       and d0.game_name = d.game_name
    left join category_revenue_daily r
        on d0.dt = r.dt
       and d0.game_name = r.game_name
    left join category_attribution_daily a
        on d0.dt = a.dt
       and d0.game_name = a.game_name
    left join interest_category_daily i
        on d0.dt = i.dt
       and d0.game_name = i.game_name
)

select
    `日期`,
    `数据粒度`,
    `品类`,
    `主播uid`,
    `主播昵称`,
    `当天是否开播`,
    `开播时长_小时`,
    `当天平均acu`,
    `dau`,
    `打赏流水`,
    `打赏人数`,
    `人均打赏流水`,
    `人均观时_分钟`,
    `归因人数`,
    `兴趣用户数`,
    `非lol兴趣用户数`
from result
;
