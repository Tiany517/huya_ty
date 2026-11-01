-- ============================================
-- 建表：不朽杯活动用户特征宽表
-- ============================================
create table if not exists zhgametemp.zty_user_features_for_immortal_cup (
    yyuid                   string      comment '用户UID'
    ,is_attend              bigint      comment '是否当天首次参与不朽杯 1=是 0=从未参与'
    ,is_interest_dota2      bigint      comment '是否Dota2兴趣用户 1=是 0=否'
    -- 前7天观看行为
    ,before_watch_duration  double      comment '前7天观看总时长(分钟)'
    ,before_watch_dcnt      double      comment '前7天观看天数'
    ,before_watch_anchorcnt double      comment '前7天观看主播数'
    ,before_watch_gamecnt   double      comment '前7天观看游戏数'
    -- 前7天付费
    ,before_consume_amount  double      comment '前7天消费金额'
    -- 前7天活跃
    ,before_active_dcnt     double      comment '前7天活跃天数'
    -- 前7天归属游戏
    ,before_main_gameid     double      comment '前7天观看时长最长的游戏ID'
    -- 后7天观看行为
    ,after_watch_duration   double      comment '后7天观看总时长(分钟)'
    ,after_watch_dcnt       double      comment '后7天观看天数'
    ,after_watch_anchorcnt  double      comment '后7天观看主播数'
    ,after_watch_gamecnt    double      comment '后7天观看游戏数'
    -- 后7天付费
    ,after_consume_amount   double      comment '后7天消费金额'
    -- 后7天活跃
    ,after_active_dcnt      double      comment '后7天活跃天数'
)
PARTITIONED BY (dt string)
STORED AS ORC;


-- ============================================
-- 每日ETL：插入当天数据
-- ============================================
with user_info as (
    -- 当天活跃用户 + 首次参与不朽杯标记
    select
        a.dt,
        a.yyuid,
        b.first_attend_dt,
        if(b.first_attend_dt = a.dt, 1, 0) as is_attend
    from (
        -- 当天活跃用户
        select
            dt,
            user_uid as yyuid
        from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
        where dt = '${tdate?string('yyyy-MM-dd')}'
          and is_black_ukey = 0
          and user_uid is not null
          and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi')
        group by dt, user_uid
    ) a
    left join (
        -- 首次参与不朽杯的日期
        select
            uid,
            attend_dt as first_attend_dt
        from (
            select
                uid,
                date_trunc('day', auto_updatetime) as attend_dt,
                row_number() over (partition by uid order by auto_updatetime asc) as rnk
            from paimon.gamelive.t_ActUserSignIn_0_1753430895206
            where activityId = 1185
        ) t
        where rnk = 1
    ) b
    on a.yyuid = b.uid
    -- 只看当天首次参与 或 从未参与的用户
    where (b.first_attend_dt = a.dt) or (b.first_attend_dt is null)
)


-- ============================================
-- 前7天：观看行为
-- ============================================
, before7d_watch_info as (
    select
        user_yyuid as yyuid,
        sum(user_duration) / 60000                                     as before_watch_duration,
        count(distinct dt)                                             as before_watch_dcnt,
        count(distinct if(user_duration > 0, luid, null))              as before_watch_anchorcnt,
        count(distinct if(user_duration > 0, igameid, null))           as before_watch_gamecnt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '${DateUtils.addDays(tdate, -7)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
      and length(dt) = 10
      and tag = 'gameid'
      and htime = 'session'
      and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios')
    group by user_yyuid
)


-- ============================================
-- 前7天：归属游戏（用于判断Dota2兴趣）
-- ============================================
, april_gamebelong_info as (
    select
        yyuid,
        igameid as before_main_gameid
    from (
        select
            user_yyuid as yyuid,
            igameid,
            sum(user_duration) as total_duration,
            row_number() over (partition by user_yyuid order by sum(user_duration) desc) as rn
        from gamelive.dwt_huya_ayyuid_session_from_server_with_user
        where dt >= '2026-04-01' and dt <= '2026-04-30'
          and tag = 'gameid'
          and htime = 'session'
          and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios')
        group by user_yyuid, igameid
    ) t
    where rn = 1
)



-- ============================================
-- 前7天：付费
-- ============================================
, before7d_consume_info as (
    select
        user_uid as yyuid,
        sum(user_consume_amount) as before_consume_amount
    from gamelive.dws_huya_revenue_detail_d_i
    where dt between '${DateUtils.addDays(tdate, -7)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
      and user_consume_amount > 0
    group by user_uid
)


-- ============================================
-- 前7天：活跃天数
-- ============================================
, before7d_actived_info as (
    select
        user_uid as yyuid,
        count(distinct dt) as before_active_dcnt
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt between '${DateUtils.addDays(tdate, -7)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
      and is_black_ukey = 0
      and user_uid is not null
    group by user_uid
)


-- ============================================
-- 后7天：观看行为
-- ============================================
, after7d_watch_info as (
    select
        user_yyuid as yyuid,
        sum(user_duration) / 60000                                     as after_watch_duration,
        count(distinct dt)                                             as after_watch_dcnt,
        count(distinct if(user_duration > 0, luid, null))              as after_watch_anchorcnt,
        count(distinct if(user_duration > 0, igameid, null))           as after_watch_gamecnt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, 7)?string('yyyy-MM-dd')}'
      and length(dt) = 10
      and tag = 'gameid'
      and htime = 'session'
      and user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios')
    group by user_yyuid
)


-- ============================================
-- 后7天：付费
-- ============================================
, after7d_consume_info as (
    select
        user_uid as yyuid,
        sum(user_consume_amount) as after_consume_amount
    from gamelive.dws_huya_revenue_detail_d_i
    where dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, 7)?string('yyyy-MM-dd')}'
      and user_consume_amount > 0
    group by user_uid
)


-- ============================================
-- 后7天：活跃天数
-- ============================================
, after7d_actived_info as (
    select
        user_uid as yyuid,
        count(distinct dt) as after_active_dcnt
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, 7)?string('yyyy-MM-dd')}'
      and is_black_ukey = 0
      and user_uid is not null
    group by user_uid
)


-- ============================================
-- 最终输出：宽表
-- ============================================
insert overwrite table zhgametemp.zty_user_features_for_immortal_cup partition(dt='${tdate?string('yyyy-MM-dd')}')

select
    a.yyuid,
    a.is_attend,
    case when d.before_main_gameid = 7 then 1 else 0 end as is_interest_dota2,
    -- 前7天
    b.before_watch_duration,
    b.before_watch_dcnt,
    b.before_watch_anchorcnt,
    b.before_watch_gamecnt,
    coalesce(f.before_consume_amount, 0) as before_consume_amount,
    coalesce(g.before_active_dcnt, 0) as before_active_dcnt,
    d.before_main_gameid,
    -- 后7天
    e.after_watch_duration,
    e.after_watch_dcnt,
    e.after_watch_anchorcnt,
    e.after_watch_gamecnt,
    coalesce(h.after_consume_amount, 0) as after_consume_amount,
    coalesce(i.after_active_dcnt, 0) as after_active_dcnt
from user_info a
left join before7d_watch_info b
    on a.yyuid = b.yyuid
left join april_gamebelong_info d
    on a.yyuid = d.yyuid
left join before7d_consume_info f
    on a.yyuid = f.yyuid
left join before7d_actived_info g
    on a.yyuid = g.yyuid
left join after7d_watch_info e
    on a.yyuid = e.yyuid
left join after7d_consume_info h
    on a.yyuid = h.yyuid
left join after7d_actived_info i
    on a.yyuid = i.yyuid
;