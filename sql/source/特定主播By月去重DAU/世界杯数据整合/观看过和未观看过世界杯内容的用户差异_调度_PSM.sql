create table if not exists zhgametemp.zty_user_features_for_world_cup_user_V2 (
     user_ukey                string      comment '用户设备ID'

    ,before6d_watch_duration  double      comment '前6天观看总时长(分钟)'
    ,before6d_watch_dcnt      double      comment '前6天观看天数'
    ,before6d_watch_anchorcnt double      comment '前6天观看主播数'
    ,before6d_watch_gamecnt   double      comment '前6天观看游戏数'
    ,before6d_consume_amount  double      comment '前6天消费金额'
    ,before6d_active_dcnt     double      comment '前6天活跃天数'
    ,before_main_gameid       double      comment '2026年5月观看时长最长的游戏ID'

    ,after6d_watch_duration   double      comment '后6天观看总时长(分钟)'
    ,after6d_watch_dcnt       double      comment '后6天观看天数'
    ,after6d_watch_anchorcnt  double      comment '后6天观看主播数'
    ,after6d_watch_gamecnt    double      comment '后6天观看游戏数'
    ,after6d_consume_amount   double      comment '后6天消费金额'
    ,after6d_active_dcnt      double      comment '后6天活跃天数'

    ,is_treatment             double      comment 'tdate当天是否观看世界杯内容：1=观看，0=未观看'
    ,is_6d_retain             double      comment 'D6留存：tdate+6当天是否活跃，1=活跃，0=未活跃'
)
partitioned by (
    dt string comment 'cohort日期/处理发生日，即tdate'
)
stored as orc
;

with

-- ============================================================
-- 1. Treatment：tdate当天观看世界杯内容的用户
-- ============================================================
world_cup_user as (
  
    select distinct
        user_ukey
    from gamelive.dws_huya_user_behavior_d_i
    where dt = '${tdate?string('yyyy-MM-dd')}'
      and product in ('huya_andriod', 'huya_ios', 'hmos_kiwi')
      and data_type = 'video_session'
      and live_content_type = '视频'
      and content_id <> 0
      and vid_can_play = 1
      and watch_cnt > 0
      and watch_duration > 0
      and (
          implicit_tags like '%美加墨世界杯%'
          or implicit_tags like '%世界杯%'
      )

    union all

    select distinct
        user_ukey
    from gamelive.dws_huya_user_behavior_d_i
    where dt = '${tdate?string('yyyy-MM-dd')}'
      and product in ('huya_andriod', 'huya_ios', 'hmos_kiwi')
      and data_type = 'live_watch_session'
      and live_content_type = '直播'
      and watch_cnt > 0
      and watch_duration > 0
      and (
          implicit_tags like '%美加墨世界杯%'
          or implicit_tags like '%世界杯%'
      )
),

-- ============================================================
-- 2. tdate当天活跃用户：PSM总样本池
--    Treatment=0的对照用户从这里产生
-- ============================================================
active_base_user as (
    select distinct
        user_ukey
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt = '${tdate?string('yyyy-MM-dd')}'
      and is_black_ukey = 0
      and user_ukey is not null
),

-- ============================================================
-- 3. 合并样本池
--    union用于兜底：确保世界杯观看用户进入样本
-- ============================================================
cohort_base_user as (
    select user_ukey
    from active_base_user

    union

    select user_ukey
    from world_cup_user
),

-- ============================================================
-- 4. 为全部样本打Treatment标签
-- ============================================================
user_info as (
    select
        a.user_ukey,
        cast(
            case
                when b.user_ukey is not null then 1
                else 0
            end
            as double
        ) as is_treatment
    from cohort_base_user a
    left join (
        select distinct
            user_ukey
        from world_cup_user
    ) b
        on a.user_ukey = b.user_ukey
),

-- ============================================================
-- 5. 前6天观看行为：PSM匹配特征
--    窗口：tdate-6 ~ tdate-1
-- ============================================================
before6d_watch_info as (
    select
        user_ukey,
        sum(user_duration) / 60000
            as before6d_watch_duration,
        count(distinct dt)
            as before6d_watch_dcnt,
        count(distinct if(user_duration > 0, luid, null))
            as before6d_watch_anchorcnt,
        count(distinct if(user_duration > 0, igameid, null))
            as before6d_watch_gamecnt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
      and length(dt) = 10
      and tag = 'gameid'
      and htime = 'session'
      and user_product in (
          'huya_andriod',
          'huya_ipad',
          'huya_pad',
          'huya_ios'
      )
    group by user_ukey
),

-- ============================================================
-- 6. 前6天消费：PSM匹配特征
--    窗口：tdate-6 ~ tdate-1
-- ============================================================
before6d_consume_info as (
    select
        ext['ukey'] as user_ukey,
        sum(user_consume_amount) as before6d_consume_amount
    from gamelive.dws_huya_revenue_detail_d_i
    where dt between '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
      and user_consume_amount > 0
    group by ext['ukey']
),

-- ============================================================
-- 7. 前6天活跃天数：PSM匹配特征
--    窗口：tdate-6 ~ tdate-1
-- ============================================================
before6d_active_info as (
    select
        user_ukey,
        count(distinct dt) as before6d_active_dcnt
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt between '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
      and is_black_ukey = 0
      and user_ukey is not null
    group by user_ukey
),

-- ============================================================
-- 8. 固定2026年5月主游戏偏好：PSM匹配特征
-- ============================================================
may_game_duration as (
    select
        user_ukey,
        igameid,
        sum(user_duration) as total_duration
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt >= '2026-05-01'
      and dt < '2026-06-01'
      and length(dt) = 10
      and tag = 'gameid'
      and htime = 'session'
      and user_product in (
          'huya_andriod',
          'huya_ipad',
          'huya_pad',
          'huya_ios'
      )
    group by
        user_ukey,
        igameid
),

may_gamebelong_info as (
    select
        user_ukey,
        cast(igameid as double) as before_main_gameid
    from (
        select
            user_ukey,
            igameid,
            total_duration,
            row_number() over (
                partition by user_ukey
                order by total_duration desc, igameid
            ) as rn
        from may_game_duration
    ) t
    where rn = 1
),

-- ============================================================
-- 9. 后6天观看行为：结果/机制分析，不可用于PSM
--    窗口：tdate+1 ~ tdate+6
-- ============================================================
after6d_watch_info as (
    select
        user_ukey,
        sum(user_duration) / 60000
            as after6d_watch_duration,
        count(distinct dt)
            as after6d_watch_dcnt,
        count(distinct if(user_duration > 0, luid, null))
            as after6d_watch_anchorcnt,
        count(distinct if(user_duration > 0, igameid, null))
            as after6d_watch_gamecnt
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
      and length(dt) = 10
      and tag = 'gameid'
      and htime = 'session'
      and user_product in (
          'huya_andriod',
          'huya_ipad',
          'huya_pad',
          'huya_ios'
      )
    group by user_ukey
),

-- ============================================================
-- 10. 后6天消费：结果/机制分析，不可用于PSM
--     窗口：tdate+1 ~ tdate+6
-- ============================================================
after6d_consume_info as (
    select
        ext['ukey'] as user_ukey,
        sum(user_consume_amount) as after6d_consume_amount
    from gamelive.dws_huya_revenue_detail_d_i
    where dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
      and user_consume_amount > 0
    group by ext['ukey']
),

-- ============================================================
-- 11. 后6天活跃天数：结果/机制分析，不可用于PSM
--     窗口：tdate+1 ~ tdate+6
-- ============================================================
after6d_active_info as (
    select
        user_ukey,
        count(distinct dt) as after6d_active_dcnt
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
      and is_black_ukey = 0
      and user_ukey is not null
    group by user_ukey
),

-- ============================================================
-- 12. D6留存：结果变量
--     仅看 tdate+6 当天是否活跃
-- ============================================================
d6_active_info as (
    select distinct
        user_ukey,
        cast(1 as double) as is_6d_retain
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt = '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
      and is_black_ukey = 0
      and user_ukey is not null
)

insert overwrite table zhgametemp.zty_user_features_for_world_cup_user_V2
partition(dt='${tdate?string('yyyy-MM-dd')}')

select
    a.user_ukey,

    -- 前6天特征：PSM匹配变量
    coalesce(b.before6d_watch_duration, 0)
        as before6d_watch_duration,
    coalesce(b.before6d_watch_dcnt, 0)
        as before6d_watch_dcnt,
    coalesce(b.before6d_watch_anchorcnt, 0)
        as before6d_watch_anchorcnt,
    coalesce(b.before6d_watch_gamecnt, 0)
        as before6d_watch_gamecnt,
    coalesce(f.before6d_consume_amount, 0)
        as before6d_consume_amount,
    coalesce(g.before6d_active_dcnt, 0)
        as before6d_active_dcnt,
    coalesce(d.before_main_gameid, 0)
        as before_main_gameid,

    -- 后6天结果/机制字段
    coalesce(e.after6d_watch_duration, 0)
        as after6d_watch_duration,
    coalesce(e.after6d_watch_dcnt, 0)
        as after6d_watch_dcnt,
    coalesce(e.after6d_watch_anchorcnt, 0)
        as after6d_watch_anchorcnt,
    coalesce(e.after6d_watch_gamecnt, 0)
        as after6d_watch_gamecnt,
    coalesce(h.after6d_consume_amount, 0)
        as after6d_consume_amount,
    coalesce(i.after6d_active_dcnt, 0)
        as after6d_active_dcnt,

    -- Treatment与D6留存
    a.is_treatment
        as is_treatment,
    coalesce(j.is_6d_retain, 0)
        as is_6d_retain

from user_info a
left join before6d_watch_info b
    on a.user_ukey = b.user_ukey
left join may_gamebelong_info d
    on a.user_ukey = d.user_ukey
left join before6d_consume_info f
    on a.user_ukey = f.user_ukey
left join before6d_active_info g
    on a.user_ukey = g.user_ukey
left join after6d_watch_info e
    on a.user_ukey = e.user_ukey
left join after6d_consume_info h
    on a.user_ukey = h.user_ukey
left join after6d_active_info i
    on a.user_ukey = i.user_ukey
left join d6_active_info j
    on a.user_ukey = j.user_ukey
;