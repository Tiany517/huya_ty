create table if not exists zhgametemp.zty_ai_gift_psm_user_revenue_breakdown_v5 (
    user_uid string,
    user_ukey string,
    is_treatment double,
    user_group string comment '曝光且支付/曝光未支付/未曝光未支付',

    before6d_consume_amount double,
    before6d_consume_order_cnt bigint,
    before6d_ai_consume_amount double,
    before6d_ai_consume_order_cnt bigint,
    before6d_normal_consume_amount double,
    before6d_normal_consume_order_cnt bigint,

    before13d_consume_amount double,
    before13d_consume_order_cnt bigint,
    before13d_ai_consume_amount double,
    before13d_ai_consume_order_cnt bigint,
    before13d_normal_consume_amount double,
    before13d_normal_consume_order_cnt bigint,

    before20d_consume_amount double,
    before20d_consume_order_cnt bigint,
    before20d_ai_consume_amount double,
    before20d_ai_consume_order_cnt bigint,
    before20d_normal_consume_amount double,
    before20d_normal_consume_order_cnt bigint,

    before6d_active_dcnt bigint,
    before6d_watch_dcnt bigint,
    before6d_watch_duration double,
    before6d_watch_anchorcnt bigint,
    before6d_watch_gamecnt bigint,

    before13d_active_dcnt bigint,
    before13d_watch_dcnt bigint,
    before13d_watch_duration double,
    before13d_watch_anchorcnt bigint,
    before13d_watch_gamecnt bigint,

    before20d_active_dcnt bigint,
    before20d_watch_dcnt bigint,
    before20d_watch_duration double,
    before20d_watch_anchorcnt bigint,
    before20d_watch_gamecnt bigint,

    before30d_active_dcnt bigint,
    before30d_watch_dcnt bigint,
    before30d_watch_duration double,
    before30d_watch_anchorcnt bigint,
    before30d_watch_gamecnt bigint,

    after6d_consume_amount double,
    after6d_consume_order_cnt bigint,
    after6d_ai_consume_amount double,
    after6d_ai_consume_order_cnt bigint,
    after6d_normal_consume_amount double,
    after6d_normal_consume_order_cnt bigint,

    after13d_consume_amount double,
    after13d_consume_order_cnt bigint,
    after13d_ai_consume_amount double,
    after13d_ai_consume_order_cnt bigint,
    after13d_normal_consume_amount double,
    after13d_normal_consume_order_cnt bigint,

    after20d_consume_amount double,
    after20d_consume_order_cnt bigint,
    after20d_ai_consume_amount double,
    after20d_ai_consume_order_cnt bigint,
    after20d_normal_consume_amount double,
    after20d_normal_consume_order_cnt bigint,

    after6d_active_dcnt bigint,
    after6d_watch_dcnt bigint,
    after6d_watch_duration double,
    after6d_watch_anchorcnt bigint,
    after6d_watch_gamecnt bigint,

    after13d_active_dcnt bigint,
    after13d_watch_dcnt bigint,
    after13d_watch_duration double,
    after13d_watch_anchorcnt bigint,
    after13d_watch_gamecnt bigint,

    after20d_active_dcnt bigint,
    after20d_watch_dcnt bigint,
    after20d_watch_duration double,
    after20d_watch_anchorcnt bigint,
    after20d_watch_gamecnt bigint
)
comment 'AI工坊PSM用户消费、活跃、观看前置及后置指标表v5'
partitioned by (
    dt string comment 'cohort日期，即tdate'
)
stored as orc;


with item_dim as (
    select
        dt,
        item_id,
        max(
            case
                when item_level = '礼物'
                 and ext['is_ai'] = '1'
                then 1
                else 0
            end
        ) as is_ai
    from gamelive.dim_huya_item_d_a
    where dt between
          '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}'
          and
          '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}'
    group by
        dt,
        item_id
),

treatment_users as (
    -- 实验组：调度日被AI工坊曝光，且当天真实支付AI礼物
    select
        user_ukey,
        max(user_uid) as user_uid
    from zhgametemp.zty_ads_huya_ai_gift_user_detail_0901_v1
    where dt = '${tdate?string('yyyy-MM-dd')}'
      and user_ukey is not null
      and is_exposure = true
      and is_pay = true
    group by user_ukey
),

active_base_users as (
    -- 对照组候选池：调度日有效活跃用户
    select distinct
        user_ukey
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt = '${tdate?string('yyyy-MM-dd')}'
      and product in (
          'huya_andriod',
          'huya_ipad',
          'huya_pad',
          'huya_ios'
      )
      and is_black_ukey = 0
      and user_ukey is not null
),

ai_user_status as (
    -- 识别调度日用户是否曝光或支付AI礼物，用于拆分三组
    select
        max(user_uid) as user_uid,
        user_ukey,
        max(
            case
                when is_exposure = true then 1
                else 0
            end
        ) as has_exposure,
        max(
            case
                when is_pay = true then 1
                else 0
            end
        ) as has_ai_pay
    from zhgametemp.zty_ads_huya_ai_gift_user_detail_0901_v1
    where dt = '${tdate?string('yyyy-MM-dd')}'
      and user_ukey is not null
    group by user_ukey
),

user_info as (
    -- 三组用户：1=曝光且支付；0=曝光未支付；0=未曝光未支付
    select
        user_uid,
        user_ukey,
        cast(1 as double) as is_treatment,
        cast('曝光且支付' as string) as user_group
    from treatment_users

    union all

    select
        b.user_uid,
        b.user_ukey,
        cast(0 as double) as is_treatment,
        cast('曝光未支付' as string) as user_group
    from ai_user_status b
    where b.has_exposure = 1
      and b.has_ai_pay = 0

    union all

    select
        cast(null as string) as user_uid,
        a.user_ukey,
        cast(0 as double) as is_treatment,
        cast('未曝光未支付' as string) as user_group
    from active_base_users a
    left join ai_user_status b
        on a.user_ukey = b.user_ukey
    where coalesce(b.has_exposure, 0) = 0
      and coalesce(b.has_ai_pay, 0) = 0
),

consume_detail as (
    -- 扫描调度日前30天至调度日后20天的礼物打赏
    select
        u.user_uid,
        u.user_ukey,
        u.is_treatment,
        u.user_group,
        r.dt,
        r.order_id,
        r.user_consume_amount,
        coalesce(i.is_ai, 0) as is_ai
    from user_info u
    inner join gamelive.dws_huya_revenue_detail_d_i r
        on r.ext['ukey'] = u.user_ukey
    left join item_dim i
        on r.dt = i.dt
       and r.item_id = i.item_id
    where r.dt between
          '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}'
          and
          '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}'
      and r.consume_order_type = '礼物'
      and r.user_consume_amount > 0
      and r.order_id is not null
      and r.ext['ukey'] is not null
),

user_consume_panel as (
    -- 保留没有打赏记录的用户
    select
        u.user_uid,
        u.user_ukey,
        u.is_treatment,
        u.user_group,
        d.dt,
        d.order_id,
        d.user_consume_amount,
        d.is_ai
    from user_info u
    left join consume_detail d
        on u.user_ukey = d.user_ukey
),

consume_metrics as (
    select
        user_uid,
        user_ukey,
        is_treatment,
        user_group,

        sum(case when dt between
            '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as before6d_consume_amount,

        count(distinct case when dt between
            '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then order_id end) as before6d_consume_order_cnt,

        sum(case when is_ai = 1 and dt between
            '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as before6d_ai_consume_amount,

        count(distinct case when is_ai = 1 and dt between
            '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then order_id end) as before6d_ai_consume_order_cnt,

        sum(case when is_ai = 0 and dt between
            '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as before6d_normal_consume_amount,

        count(distinct case when is_ai = 0 and dt between
            '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then order_id end) as before6d_normal_consume_order_cnt,

        sum(case when dt between
            '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as before13d_consume_amount,

        count(distinct case when dt between
            '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then order_id end) as before13d_consume_order_cnt,

        sum(case when is_ai = 1 and dt between
            '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as before13d_ai_consume_amount,

        count(distinct case when is_ai = 1 and dt between
            '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then order_id end) as before13d_ai_consume_order_cnt,

        sum(case when is_ai = 0 and dt between
            '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as before13d_normal_consume_amount,

        count(distinct case when is_ai = 0 and dt between
            '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then order_id end) as before13d_normal_consume_order_cnt,

        sum(case when dt between
            '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as before20d_consume_amount,

        count(distinct case when dt between
            '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then order_id end) as before20d_consume_order_cnt,

        sum(case when is_ai = 1 and dt between
            '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as before20d_ai_consume_amount,

        count(distinct case when is_ai = 1 and dt between
            '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then order_id end) as before20d_ai_consume_order_cnt,

        sum(case when is_ai = 0 and dt between
            '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as before20d_normal_consume_amount,

        count(distinct case when is_ai = 0 and dt between
            '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then order_id end) as before20d_normal_consume_order_cnt,

        sum(case when dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as after6d_consume_amount,

        count(distinct case when dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
            then order_id end) as after6d_consume_order_cnt,

        sum(case when is_ai = 1 and dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as after6d_ai_consume_amount,

        count(distinct case when is_ai = 1 and dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
            then order_id end) as after6d_ai_consume_order_cnt,

        sum(case when is_ai = 0 and dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as after6d_normal_consume_amount,

        count(distinct case when is_ai = 0 and dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
            then order_id end) as after6d_normal_consume_order_cnt,

        sum(case when dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as after13d_consume_amount,

        count(distinct case when dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}'
            then order_id end) as after13d_consume_order_cnt,

        sum(case when is_ai = 1 and dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as after13d_ai_consume_amount,

        count(distinct case when is_ai = 1 and dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}'
            then order_id end) as after13d_ai_consume_order_cnt,

        sum(case when is_ai = 0 and dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as after13d_normal_consume_amount,

        count(distinct case when is_ai = 0 and dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}'
            then order_id end) as after13d_normal_consume_order_cnt,

        sum(case when dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as after20d_consume_amount,

        count(distinct case when dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}'
            then order_id end) as after20d_consume_order_cnt,

        sum(case when is_ai = 1 and dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as after20d_ai_consume_amount,

        count(distinct case when is_ai = 1 and dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}'
            then order_id end) as after20d_ai_consume_order_cnt,

        sum(case when is_ai = 0 and dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}'
            then user_consume_amount else 0 end) as after20d_normal_consume_amount,

        count(distinct case when is_ai = 0 and dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}'
            then order_id end) as after20d_normal_consume_order_cnt

    from user_consume_panel
    group by
        user_uid,
        user_ukey,
        is_treatment,
        user_group
),

before_active_metrics as (
    select
        u.user_ukey,

        count(distinct case when a.dt between
            '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then a.dt end) as before6d_active_dcnt,

        count(distinct case when a.dt between
            '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then a.dt end) as before13d_active_dcnt,

        count(distinct case when a.dt between
            '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then a.dt end) as before20d_active_dcnt,

        count(distinct case when a.dt between
            '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then a.dt end) as before30d_active_dcnt

    from user_info u
    inner join gamelive.dws_huya_active_product_ukey_info_withsdk_d_i a
        on a.user_ukey = u.user_ukey
    where a.dt between
          '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}'
          and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
      and a.product in (
          'huya_andriod',
          'huya_ipad',
          'huya_pad',
          'huya_ios'
      )
      and a.is_black_ukey = 0
      and a.user_ukey is not null
    group by u.user_ukey
),

before_watch_metrics as (
    select
        u.user_ukey,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then w.dt end) as before6d_watch_dcnt,

        sum(case when w.dt between
            '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then coalesce(w.user_duration, 0) else 0 end) / 60000.0 as before6d_watch_duration,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then w.luid end) as before6d_watch_anchorcnt,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then w.sgamename end) as before6d_watch_gamecnt,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then w.dt end) as before13d_watch_dcnt,

        sum(case when w.dt between
            '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then coalesce(w.user_duration, 0) else 0 end) / 60000.0 as before13d_watch_duration,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then w.luid end) as before13d_watch_anchorcnt,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then w.sgamename end) as before13d_watch_gamecnt,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then w.dt end) as before20d_watch_dcnt,

        sum(case when w.dt between
            '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then coalesce(w.user_duration, 0) else 0 end) / 60000.0 as before20d_watch_duration,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then w.luid end) as before20d_watch_anchorcnt,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then w.sgamename end) as before20d_watch_gamecnt,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then w.dt end) as before30d_watch_dcnt,

        sum(case when w.dt between
            '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then coalesce(w.user_duration, 0) else 0 end) / 60000.0 as before30d_watch_duration,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then w.luid end) as before30d_watch_anchorcnt,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
            then w.sgamename end) as before30d_watch_gamecnt

    from user_info u
    inner join gamelive.dwt_huya_ayyuid_session_from_server_with_user w
        on w.user_ukey = u.user_ukey
    where w.dt between
          '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}'
          and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
      and w.tag = 'gameid'
      and w.htime = 'session'
      and w.user_product in (
          'huya_andriod',
          'huya_ipad',
          'huya_pad',
          'huya_ios'
      )
      and w.luid is not null
    group by u.user_ukey
),

after_active_metrics as (
    select
        u.user_ukey,

        count(distinct case when a.dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
            then a.dt end) as after6d_active_dcnt,

        count(distinct case when a.dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}'
            then a.dt end) as after13d_active_dcnt,

        count(distinct case when a.dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}'
            then a.dt end) as after20d_active_dcnt

    from user_info u
    inner join gamelive.dws_huya_active_product_ukey_info_withsdk_d_i a
        on a.user_ukey = u.user_ukey
    where a.dt between
          '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
          and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}'
      and a.product in (
          'huya_andriod',
          'huya_ipad',
          'huya_pad',
          'huya_ios'
      )
      and a.is_black_ukey = 0
      and a.user_ukey is not null
    group by u.user_ukey
),

after_watch_metrics as (
    select
        u.user_ukey,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
            then w.dt end) as after6d_watch_dcnt,

        sum(case when w.dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
            then coalesce(w.user_duration, 0) else 0 end) / 60000.0 as after6d_watch_duration,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
            then w.luid end) as after6d_watch_anchorcnt,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
            then w.sgamename end) as after6d_watch_gamecnt,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}'
            then w.dt end) as after13d_watch_dcnt,

        sum(case when w.dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}'
            then coalesce(w.user_duration, 0) else 0 end) / 60000.0 as after13d_watch_duration,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}'
            then w.luid end) as after13d_watch_anchorcnt,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}'
            then w.sgamename end) as after13d_watch_gamecnt,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}'
            then w.dt end) as after20d_watch_dcnt,

        sum(case when w.dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}'
            then coalesce(w.user_duration, 0) else 0 end) / 60000.0 as after20d_watch_duration,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}'
            then w.luid end) as after20d_watch_anchorcnt,

        count(distinct case when w.dt between
            '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
            and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}'
            then w.sgamename end) as after20d_watch_gamecnt

    from user_info u
    inner join gamelive.dwt_huya_ayyuid_session_from_server_with_user w
        on w.user_ukey = u.user_ukey
    where w.dt between
          '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
          and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}'
      and w.tag = 'gameid'
      and w.htime = 'session'
      and w.user_product in (
          'huya_andriod',
          'huya_ipad',
          'huya_pad',
          'huya_ios'
      )
      and w.luid is not null
    group by u.user_ukey
),

all_metrics as (
    select
        c.*,

        coalesce(ba.before6d_active_dcnt, 0) as before6d_active_dcnt,
        coalesce(ba.before13d_active_dcnt, 0) as before13d_active_dcnt,
        coalesce(ba.before20d_active_dcnt, 0) as before20d_active_dcnt,
        coalesce(ba.before30d_active_dcnt, 0) as before30d_active_dcnt,

        coalesce(bw.before6d_watch_dcnt, 0) as before6d_watch_dcnt,
        coalesce(bw.before6d_watch_duration, 0.0) as before6d_watch_duration,
        coalesce(bw.before6d_watch_anchorcnt, 0) as before6d_watch_anchorcnt,
        coalesce(bw.before6d_watch_gamecnt, 0) as before6d_watch_gamecnt,

        coalesce(bw.before13d_watch_dcnt, 0) as before13d_watch_dcnt,
        coalesce(bw.before13d_watch_duration, 0.0) as before13d_watch_duration,
        coalesce(bw.before13d_watch_anchorcnt, 0) as before13d_watch_anchorcnt,
        coalesce(bw.before13d_watch_gamecnt, 0) as before13d_watch_gamecnt,

        coalesce(bw.before20d_watch_dcnt, 0) as before20d_watch_dcnt,
        coalesce(bw.before20d_watch_duration, 0.0) as before20d_watch_duration,
        coalesce(bw.before20d_watch_anchorcnt, 0) as before20d_watch_anchorcnt,
        coalesce(bw.before20d_watch_gamecnt, 0) as before20d_watch_gamecnt,

        coalesce(bw.before30d_watch_dcnt, 0) as before30d_watch_dcnt,
        coalesce(bw.before30d_watch_duration, 0.0) as before30d_watch_duration,
        coalesce(bw.before30d_watch_anchorcnt, 0) as before30d_watch_anchorcnt,
        coalesce(bw.before30d_watch_gamecnt, 0) as before30d_watch_gamecnt,

        coalesce(aa.after6d_active_dcnt, 0) as after6d_active_dcnt,
        coalesce(aa.after13d_active_dcnt, 0) as after13d_active_dcnt,
        coalesce(aa.after20d_active_dcnt, 0) as after20d_active_dcnt,

        coalesce(aw.after6d_watch_dcnt, 0) as after6d_watch_dcnt,
        coalesce(aw.after6d_watch_duration, 0.0) as after6d_watch_duration,
        coalesce(aw.after6d_watch_anchorcnt, 0) as after6d_watch_anchorcnt,
        coalesce(aw.after6d_watch_gamecnt, 0) as after6d_watch_gamecnt,

        coalesce(aw.after13d_watch_dcnt, 0) as after13d_watch_dcnt,
        coalesce(aw.after13d_watch_duration, 0.0) as after13d_watch_duration,
        coalesce(aw.after13d_watch_anchorcnt, 0) as after13d_watch_anchorcnt,
        coalesce(aw.after13d_watch_gamecnt, 0) as after13d_watch_gamecnt,

        coalesce(aw.after20d_watch_dcnt, 0) as after20d_watch_dcnt,
        coalesce(aw.after20d_watch_duration, 0.0) as after20d_watch_duration,
        coalesce(aw.after20d_watch_anchorcnt, 0) as after20d_watch_anchorcnt,
        coalesce(aw.after20d_watch_gamecnt, 0) as after20d_watch_gamecnt

    from consume_metrics c
    left join before_active_metrics ba
        on c.user_ukey = ba.user_ukey
    left join before_watch_metrics bw
        on c.user_ukey = bw.user_ukey
    left join after_active_metrics aa
        on c.user_ukey = aa.user_ukey
    left join after_watch_metrics aw
        on c.user_ukey = aw.user_ukey
)

insert overwrite table zhgametemp.zty_ai_gift_psm_user_revenue_breakdown_v5
partition (dt = '${tdate?string('yyyy-MM-dd')}')
select
    user_uid,
    user_ukey,
    is_treatment,
    user_group,

    coalesce(before6d_consume_amount, 0.0),
    coalesce(before6d_consume_order_cnt, 0),
    coalesce(before6d_ai_consume_amount, 0.0),
    coalesce(before6d_ai_consume_order_cnt, 0),
    coalesce(before6d_normal_consume_amount, 0.0),
    coalesce(before6d_normal_consume_order_cnt, 0),

    coalesce(before13d_consume_amount, 0.0),
    coalesce(before13d_consume_order_cnt, 0),
    coalesce(before13d_ai_consume_amount, 0.0),
    coalesce(before13d_ai_consume_order_cnt, 0),
    coalesce(before13d_normal_consume_amount, 0.0),
    coalesce(before13d_normal_consume_order_cnt, 0),

    coalesce(before20d_consume_amount, 0.0),
    coalesce(before20d_consume_order_cnt, 0),
    coalesce(before20d_ai_consume_amount, 0.0),
    coalesce(before20d_ai_consume_order_cnt, 0),
    coalesce(before20d_normal_consume_amount, 0.0),
    coalesce(before20d_normal_consume_order_cnt, 0),

    coalesce(before6d_active_dcnt, 0),
    coalesce(before6d_watch_dcnt, 0),
    coalesce(before6d_watch_duration, 0.0),
    coalesce(before6d_watch_anchorcnt, 0),
    coalesce(before6d_watch_gamecnt, 0),

    coalesce(before13d_active_dcnt, 0),
    coalesce(before13d_watch_dcnt, 0),
    coalesce(before13d_watch_duration, 0.0),
    coalesce(before13d_watch_anchorcnt, 0),
    coalesce(before13d_watch_gamecnt, 0),

    coalesce(before20d_active_dcnt, 0),
    coalesce(before20d_watch_dcnt, 0),
    coalesce(before20d_watch_duration, 0.0),
    coalesce(before20d_watch_anchorcnt, 0),
    coalesce(before20d_watch_gamecnt, 0),

    coalesce(before30d_active_dcnt, 0),
    coalesce(before30d_watch_dcnt, 0),
    coalesce(before30d_watch_duration, 0.0),
    coalesce(before30d_watch_anchorcnt, 0),
    coalesce(before30d_watch_gamecnt, 0),

    coalesce(after6d_consume_amount, 0.0),
    coalesce(after6d_consume_order_cnt, 0),
    coalesce(after6d_ai_consume_amount, 0.0),
    coalesce(after6d_ai_consume_order_cnt, 0),
    coalesce(after6d_normal_consume_amount, 0.0),
    coalesce(after6d_normal_consume_order_cnt, 0),

    coalesce(after13d_consume_amount, 0.0),
    coalesce(after13d_consume_order_cnt, 0),
    coalesce(after13d_ai_consume_amount, 0.0),
    coalesce(after13d_ai_consume_order_cnt, 0),
    coalesce(after13d_normal_consume_amount, 0.0),
    coalesce(after13d_normal_consume_order_cnt, 0),

    coalesce(after20d_consume_amount, 0.0),
    coalesce(after20d_consume_order_cnt, 0),
    coalesce(after20d_ai_consume_amount, 0.0),
    coalesce(after20d_ai_consume_order_cnt, 0),
    coalesce(after20d_normal_consume_amount, 0.0),
    coalesce(after20d_normal_consume_order_cnt, 0),

    coalesce(after6d_active_dcnt, 0),
    coalesce(after6d_watch_dcnt, 0),
    coalesce(after6d_watch_duration, 0.0),
    coalesce(after6d_watch_anchorcnt, 0),
    coalesce(after6d_watch_gamecnt, 0),

    coalesce(after13d_active_dcnt, 0),
    coalesce(after13d_watch_dcnt, 0),
    coalesce(after13d_watch_duration, 0.0),
    coalesce(after13d_watch_anchorcnt, 0),
    coalesce(after13d_watch_gamecnt, 0),

    coalesce(after20d_active_dcnt, 0),
    coalesce(after20d_watch_dcnt, 0),
    coalesce(after20d_watch_duration, 0.0),
    coalesce(after20d_watch_anchorcnt, 0),
    coalesce(after20d_watch_gamecnt, 0)

from all_metrics;

