create table if not exists zhgametemp.zty_3anchor_event_room_psm_features_d_i (
     user_ukey                         string  comment '用户设备ID'
    ,belong_anchor_name                string  comment '2025年5月观看时长最长归属主播名称'
    ,belong_anchor_game_name           string  comment '归属主播品类'
    ,belong_luid                       double  comment '2025年5月观看时长最长归属主播luid'

    -- PSM匹配变量：tdate前29天
    ,before29d_platform_watch_duration double  comment '前29天整体观看总时长(分钟)'
    ,before29d_game_watch_duration     double  comment '前29天游戏观看总时长(分钟)'
    ,before29d_ent_watch_duration      double  comment '前29天娱乐观看总时长(分钟)'
    ,before29d_watch_dcnt              double  comment '前29天观看天数'
    ,before29d_platform_anchorcnt      double  comment '前29天整体观看主播数'
    ,before29d_game_anchorcnt          double  comment '前29天游戏观看主播数'
    ,before29d_ent_anchorcnt           double  comment '前29天娱乐观看主播数'
    ,before29d_platform_consume_amount double  comment '前29天整体打赏金额'
    ,before29d_game_consume_amount     double  comment '前29天游戏打赏金额'
    ,before29d_ent_consume_amount      double  comment '前29天娱乐打赏金额'
    ,before29d_platform_pay_flag       double  comment '前29天是否整体打赏，1=是，0=否'
    ,before29d_game_pay_flag           double  comment '前29天是否游戏打赏，1=是，0=否'
    ,before29d_ent_pay_flag            double  comment '前29天是否娱乐打赏，1=是，0=否'
    ,before29d_active_dcnt             double  comment '前29天活跃天数'

    -- 结果/机制指标：tdate后6天。金额字段为用户级金额；pay_flag字段聚合均值即用户打赏率
    ,after6d_platform_watch_duration   double  comment '后6天整体观看总时长(分钟)'
    ,after6d_game_watch_duration       double  comment '后6天游戏观看总时长(分钟)'
    ,after6d_ent_watch_duration        double  comment '后6天娱乐观看总时长(分钟)'
    ,after6d_ent_watch_anchorcnt       double  comment '后6天娱乐观看主播数'
    ,after6d_platform_watch_flag       double  comment '后6天是否整体观看，1=是，0=否'
    ,after6d_game_watch_flag           double  comment '后6天是否游戏观看，1=是，0=否'
    ,after6d_ent_watch_flag            double  comment '后6天是否娱乐观看，1=是，0=否'
    ,after6d_platform_consume_amount   double  comment '后6天整体打赏金额'
    ,after6d_game_consume_amount       double  comment '后6天游戏打赏金额'
    ,after6d_ent_consume_amount        double  comment '后6天娱乐打赏金额'
    ,after6d_platform_pay_flag         double  comment '后6天是否整体打赏，聚合均值=整体平均打赏率'
    ,after6d_game_pay_flag             double  comment '后6天是否游戏打赏，聚合均值=游戏平均打赏率'
    ,after6d_ent_pay_flag              double  comment '后6天是否娱乐打赏，聚合均值=娱乐平均打赏率'

    -- Treatment
    ,is_treatment                      double  comment 'tdate当天是否观看活动直播间creator_uid=1099531740247：1=是，0=否'
)
partitioned by (
    dt string comment 'cohort日期/处理发生日，即tdate'
)
stored as orc
;

with

-- ============================================================
-- 1. 目标归属主播：2025年5月观看时长最长归属这三位主播
-- ============================================================
anchor_list as (
    select '明凯' as anchor_name, '王者荣耀' as anchor_game_name, cast(1705516953 as bigint) as luid
    union all select '药水哥', '英雄联盟', cast(2319419933 as bigint)
    union all select 'XLX金木', '王者荣耀', cast(1199610004865 as bigint)
),

-- ============================================================
-- 2. 2025年5月用户按主播聚合观看时长，用于判断归属主播
-- ============================================================
may_user_anchor_watch as (
    select
        user_ukey,
        creator_uid as belong_luid,
        sum(watch_duration) as month_watch_duration
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2025-05-01' and '2025-05-31'
      and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
      and data_type = 'live_watch_session'
      and live_content_type = '直播'
      and is_black_ukey = 0
      and watch_cnt > 0
      and watch_duration > 0
      and user_ukey is not null
      and creator_uid is not null
    group by
        user_ukey,
        creator_uid
),

may_user_belong as (
    select
        user_ukey,
        belong_luid
    from (
        select
            user_ukey,
            belong_luid,
            month_watch_duration,
            row_number() over (
                partition by user_ukey
                order by month_watch_duration desc, belong_luid
            ) as rn
        from may_user_anchor_watch
    ) t
    where rn = 1
),

target_belong_user as (
    select
        b.user_ukey,
        a.anchor_name as belong_anchor_name,
        a.anchor_game_name as belong_anchor_game_name,
        a.luid as belong_luid
    from may_user_belong b
    inner join anchor_list a
        on b.belong_luid = a.luid
),

-- ============================================================
-- 3. tdate当天看过活动直播间的用户
-- ============================================================
event_room_user_tdate as (
    select distinct
        user_ukey
    from gamelive.dws_huya_user_behavior_d_i
    where dt = '${tdate?string('yyyy-MM-dd')}'
      and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
      and data_type = 'live_watch_session'
      and live_content_type = '直播'
      and is_black_ukey = 0
      and watch_cnt > 0
      and watch_duration > 0
      and user_ukey is not null
      and creator_uid = 1099531740247
),

event_room_user_0616_0620 as (
    -- 活动期任一天看过活动直播间的用户，用于剔除控制组污染
    select distinct
        user_ukey
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '2025-06-16' and '2025-06-20'
      and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
      and data_type = 'live_watch_session'
      and live_content_type = '直播'
      and is_black_ukey = 0
      and watch_cnt > 0
      and watch_duration > 0
      and user_ukey is not null
      and creator_uid = 1099531740247
),

-- ============================================================
-- 4. tdate当天活跃归属用户：PSM样本池
--    实验组：2025-05归属三主播，tdate当天活跃，且当天看过活动直播间
--    对照组：2025-05归属三主播，tdate当天活跃，且整个活动期都没看过活动直播间
--    适配系统按天调度：tdate建议跑 2025-06-16 至 2025-06-20
-- ============================================================
active_base_user as (
    select distinct
        user_ukey
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt = '${tdate?string('yyyy-MM-dd')}'
      and is_black_ukey = 0
      and user_ukey is not null
),

cohort_base_user as (
    -- 同为三主播归属且tdate当天活跃；
    -- 保留当天看过活动直播间的实验组，控制组限定为整个活动期都没看过活动直播间
    select
        t.user_ukey,
        t.belong_anchor_name,
        t.belong_anchor_game_name,
        t.belong_luid
    from target_belong_user t
    inner join active_base_user a
        on t.user_ukey = a.user_ukey
    left join event_room_user_tdate td
        on t.user_ukey = td.user_ukey
    left join event_room_user_0616_0620 ep
        on t.user_ukey = ep.user_ukey
    where td.user_ukey is not null
       or ep.user_ukey is null
),

user_info as (
    select
        a.user_ukey,
        a.belong_anchor_name,
        a.belong_anchor_game_name,
        cast(a.belong_luid as double) as belong_luid,
        cast(case when b.user_ukey is not null then 1 else 0 end as double) as is_treatment
    from cohort_base_user a
    left join event_room_user_tdate b
        on a.user_ukey = b.user_ukey
),

-- ============================================================
-- 6. 前29天观看行为：PSM匹配变量
--    窗口：tdate-29 ~ tdate-1
-- ============================================================
before29d_watch_info as (
    select
        user_ukey,
        sum(watch_duration) / 1000.0 / 60 as before29d_platform_watch_duration,
        sum(case
            when game_label in ('游戏', '游戏专区') then watch_duration
            else 0
        end) / 1000.0 / 60 as before29d_game_watch_duration,
        sum(case
            when game_label in ('娱乐', '娱乐专区')
             and game_id not in (2165, 1663, 2356) then watch_duration
            else 0
        end) / 1000.0 / 60 as before29d_ent_watch_duration,
        count(distinct dt) as before29d_watch_dcnt,
        count(distinct creator_uid) as before29d_platform_anchorcnt,
        count(distinct case
            when game_label in ('游戏', '游戏专区') then creator_uid
        end) as before29d_game_anchorcnt,
        count(distinct case
            when game_label in ('娱乐', '娱乐专区')
             and game_id not in (2165, 1663, 2356) then creator_uid
        end) as before29d_ent_anchorcnt
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '${DateUtils.addDays(tdate, -29)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
      and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
      and data_type = 'live_watch_session'
      and live_content_type = '直播'
      and is_black_ukey = 0
      and watch_cnt > 0
      and watch_duration > 0
      and user_ukey is not null
      and creator_uid is not null
    group by
        user_ukey
),

-- ============================================================
-- 7. 前29天消费：PSM匹配变量
-- ============================================================
before29d_consume_info as (
    select
        ext['ukey'] as user_ukey,
        sum(cast(user_consume_amount as double)) as before29d_platform_consume_amount,
        sum(case
            when game_label in ('游戏', '游戏专区') then cast(user_consume_amount as double)
            else 0
        end) as before29d_game_consume_amount,
        sum(case
            when game_label in ('娱乐', '娱乐专区')
             and game_id not in (2165, 1663, 2356) then cast(user_consume_amount as double)
            else 0
        end) as before29d_ent_consume_amount,
        max(1) as before29d_platform_pay_flag,
        max(case
            when game_label in ('游戏', '游戏专区') then 1
            else 0
        end) as before29d_game_pay_flag,
        max(case
            when game_label in ('娱乐', '娱乐专区')
             and game_id not in (2165, 1663, 2356) then 1
            else 0
        end) as before29d_ent_pay_flag
    from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i
    where dt between '${DateUtils.addDays(tdate, -29)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
      and user_consume_amount > 0
      and ext['ukey'] is not null
    group by
        ext['ukey']
),

-- ============================================================
-- 8. 前29天活跃天数：PSM匹配变量
-- ============================================================
before29d_active_info as (
    select
        user_ukey,
        count(distinct dt) as before29d_active_dcnt
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt between '${DateUtils.addDays(tdate, -29)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
      and is_black_ukey = 0
      and user_ukey is not null
    group by
        user_ukey
),

-- ============================================================
-- 9. 后6天观看行为：结果/机制指标，不进入PSM匹配
--    窗口：tdate+1 ~ tdate+6
-- ============================================================
after6d_watch_info as (
    select
        user_ukey,
        sum(watch_duration) / 1000.0 / 60 as after6d_platform_watch_duration,
        sum(case
            when game_label in ('游戏', '游戏专区') then watch_duration
            else 0
        end) / 1000.0 / 60 as after6d_game_watch_duration,
        sum(case
            when game_label in ('娱乐', '娱乐专区')
             and game_id not in (2165, 1663, 2356) then watch_duration
            else 0
        end) / 1000.0 / 60 as after6d_ent_watch_duration,
        count(distinct case
            when game_label in ('娱乐', '娱乐专区')
             and game_id not in (2165, 1663, 2356) then creator_uid
        end) as after6d_ent_watch_anchorcnt,
        max(1) as after6d_platform_watch_flag,
        max(case
            when game_label in ('游戏', '游戏专区') then 1
            else 0
        end) as after6d_game_watch_flag,
        max(case
            when game_label in ('娱乐', '娱乐专区')
             and game_id not in (2165, 1663, 2356) then 1
            else 0
        end) as after6d_ent_watch_flag
    from gamelive.dws_huya_user_behavior_d_i
    where dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
      and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios', 'hmos_kiwi')
      and data_type = 'live_watch_session'
      and live_content_type = '直播'
      and is_black_ukey = 0
      and watch_cnt > 0
      and watch_duration > 0
      and user_ukey is not null
      and creator_uid is not null
    group by
        user_ukey
),

-- ============================================================
-- 10. 后6天消费：结果/机制指标，不进入PSM匹配
-- ============================================================
after6d_consume_info as (
    select
        ext['ukey'] as user_ukey,
        sum(cast(user_consume_amount as double)) as after6d_platform_consume_amount,
        sum(case
            when game_label in ('游戏', '游戏专区') then cast(user_consume_amount as double)
            else 0
        end) as after6d_game_consume_amount,
        sum(case
            when game_label in ('娱乐', '娱乐专区')
             and game_id not in (2165, 1663, 2356) then cast(user_consume_amount as double)
            else 0
        end) as after6d_ent_consume_amount,
        max(1) as after6d_platform_pay_flag,
        max(case
            when game_label in ('游戏', '游戏专区') then 1
            else 0
        end) as after6d_game_pay_flag,
        max(case
            when game_label in ('娱乐', '娱乐专区')
             and game_id not in (2165, 1663, 2356) then 1
            else 0
        end) as after6d_ent_pay_flag
    from zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i
    where dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}'
                 and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}'
      and user_consume_amount > 0
      and ext['ukey'] is not null
    group by
        ext['ukey']
)

insert overwrite table zhgametemp.zty_3anchor_event_room_psm_features_d_i
partition (
    dt = '${tdate?string('yyyy-MM-dd')}'
)

select
    a.user_ukey,
    a.belong_anchor_name,
    a.belong_anchor_game_name,
    a.belong_luid,

    -- 前29天：PSM匹配变量
    coalesce(b.before29d_platform_watch_duration, 0.0) as before29d_platform_watch_duration,
    coalesce(b.before29d_game_watch_duration, 0.0) as before29d_game_watch_duration,
    coalesce(b.before29d_ent_watch_duration, 0.0) as before29d_ent_watch_duration,
    coalesce(b.before29d_watch_dcnt, 0.0) as before29d_watch_dcnt,
    coalesce(b.before29d_platform_anchorcnt, 0.0) as before29d_platform_anchorcnt,
    coalesce(b.before29d_game_anchorcnt, 0.0) as before29d_game_anchorcnt,
    coalesce(b.before29d_ent_anchorcnt, 0.0) as before29d_ent_anchorcnt,
    coalesce(c.before29d_platform_consume_amount, 0.0) as before29d_platform_consume_amount,
    coalesce(c.before29d_game_consume_amount, 0.0) as before29d_game_consume_amount,
    coalesce(c.before29d_ent_consume_amount, 0.0) as before29d_ent_consume_amount,
    coalesce(c.before29d_platform_pay_flag, 0.0) as before29d_platform_pay_flag,
    coalesce(c.before29d_game_pay_flag, 0.0) as before29d_game_pay_flag,
    coalesce(c.before29d_ent_pay_flag, 0.0) as before29d_ent_pay_flag,
    coalesce(d.before29d_active_dcnt, 0.0) as before29d_active_dcnt,

    -- 后6天：结果/机制指标
    coalesce(e.after6d_platform_watch_duration, 0.0) as after6d_platform_watch_duration,
    coalesce(e.after6d_game_watch_duration, 0.0) as after6d_game_watch_duration,
    coalesce(e.after6d_ent_watch_duration, 0.0) as after6d_ent_watch_duration,
    coalesce(e.after6d_ent_watch_anchorcnt, 0.0) as after6d_ent_watch_anchorcnt,
    coalesce(e.after6d_platform_watch_flag, 0.0) as after6d_platform_watch_flag,
    coalesce(e.after6d_game_watch_flag, 0.0) as after6d_game_watch_flag,
    coalesce(e.after6d_ent_watch_flag, 0.0) as after6d_ent_watch_flag,
    coalesce(f.after6d_platform_consume_amount, 0.0) as after6d_platform_consume_amount,
    coalesce(f.after6d_game_consume_amount, 0.0) as after6d_game_consume_amount,
    coalesce(f.after6d_ent_consume_amount, 0.0) as after6d_ent_consume_amount,
    coalesce(f.after6d_platform_pay_flag, 0.0) as after6d_platform_pay_flag,
    coalesce(f.after6d_game_pay_flag, 0.0) as after6d_game_pay_flag,
    coalesce(f.after6d_ent_pay_flag, 0.0) as after6d_ent_pay_flag,

    -- Treatment
    a.is_treatment as is_treatment

from user_info a
left join before29d_watch_info b
    on a.user_ukey = b.user_ukey
left join before29d_consume_info c
    on a.user_ukey = c.user_ukey
left join before29d_active_info d
    on a.user_ukey = d.user_ukey
left join after6d_watch_info e
    on a.user_ukey = e.user_ukey
left join after6d_consume_info f
    on a.user_ukey = f.user_ukey
;
