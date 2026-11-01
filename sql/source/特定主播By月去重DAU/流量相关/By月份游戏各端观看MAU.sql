with base as (
    select
        dt,
        -- 全量MAU：不区分端口
        count(distinct user_ukey) as full_user_cnt,
        -- web端
        count(distinct case
            when user_product in ('huya_flashexternal', 'huya_flash', 'huyawap', 'huya_web') then user_ukey
        end) as web_user_cnt,
        -- app端
        count(distinct case
            when user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios') then user_ukey
        end) as app_user_cnt,
        -- 客户端：PC + APP + TV等
        count(distinct case
            when user_product in ('huya_pcexe', 'huya_andriod', 'huya_android_tv', 'huya_ipad', 'huya_pad', 'huya_ios', 'huyapcmini_pc', 'smtv_androidtv', 'hmos_kiwi') then user_ukey
        end) as client_user_cnt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where
        dt between '2026-01-01' and '2026-06-21'
        and tag = 'gameid'
        and htime = 'session'
    group by dt
),

mth_mau as (
    select
        date_trunc('month', cast(dt as date)) as mth,
        '全量' as user_product,
        sum(full_user_cnt) as mau
    from base
    group by date_trunc('month', cast(dt as date))

    union all

    select
        date_trunc('month', cast(dt as date)) as mth,
        'web端' as user_product,
        sum(web_user_cnt) as mau
    from base
    group by date_trunc('month', cast(dt as date))

    union all

    select
        date_trunc('month', cast(dt as date)) as mth,
        'app端' as user_product,
        sum(app_user_cnt) as mau
    from base
    group by date_trunc('month', cast(dt as date))

    union all

    select
        date_trunc('month', cast(dt as date)) as mth,
        '客户端' as user_product,
        sum(client_user_cnt) as mau
    from base
    group by date_trunc('month', cast(dt as date))
)

select *
from mth_mau
order by mth, user_product