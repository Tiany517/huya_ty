-- 参数化：运行前替换 {{RELATED_STREAMER_LUID}} 与 {{TARGET_STREAMER_LUID}}。
-- 粒度：输入为日×用户；输出为周。先保留 ukey 明细，再在最终查询去重。
with related_belongs_user as (
    select
        dt,
        ukey
    from zhgametemp.cwq_huya_ukey_shichang_luid_gameid_guishu_day_v1
    where dt >= '2026-04-01'
      and dt <= '2026-05-31'
      and luid = cast('{{RELATED_STREAMER_LUID}}' as bigint)
    group by dt, ukey
),

target_viewed_user as (
    select distinct
        dt,
        user_ukey
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt >= '2026-04-01'
      and dt <= '2026-05-31'
      and tag = 'gameid'
      and htime = 'session'
      and user_product in (
          'huya_pcexe', 'huya_andriod', 'huya_android_tv', 'huya_ipad',
          'huya_pad', 'huya_ios', 'huyapcmini_pc', 'smtv_androidtv', 'hmos_kiwi'
      )
      and luid = cast('{{TARGET_STREAMER_LUID}}' as bigint)
),

related_left as (
    select
        a.dt,
        a.ukey,
        b.user_ukey as target_user_ukey
    from related_belongs_user a
    left join target_viewed_user b
      on a.dt = b.dt
     and a.ukey = b.user_ukey
)

select
    date_trunc('week', cast(dt as date)) as week_dt,
    count(distinct ukey) as related_belongs_user_cnt,
    count(distinct target_user_ukey) as related_users_viewing_target_cnt
from related_left
group by date_trunc('week', cast(dt as date))
order by week_dt;
