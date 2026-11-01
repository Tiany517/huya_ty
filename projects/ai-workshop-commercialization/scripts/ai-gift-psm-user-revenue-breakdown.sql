-- ============================================================
-- AI工坊 PSM 用户特征表 v2
-- 用途：为同日用户的 PSM / DID 提供消费、活跃、观看前置特征
-- 调度日期：${tdate?string('yyyy-MM-dd')}
-- 注意：后20日结果要求 tdate+20 数据已经到齐
-- ============================================================

create table if not exists zhgametemp.zty_ai_gift_psm_user_revenue_breakdown_v2 (
    user_uid string comment '用户uid',
    user_ukey string comment '用户设备标识',
    is_treatment double comment '是否实验组，1=当日曝光且支付AI礼物，0=当日活跃但未曝光且未支付AI礼物',

    before6d_consume_amount double comment '前6天整体打赏金额',
    before6d_consume_order_cnt bigint comment '前6天整体打赏次数',
    before6d_ai_consume_amount double comment '前6天AI礼物打赏金额',
    before6d_ai_consume_order_cnt bigint comment '前6天AI礼物打赏次数',
    before6d_normal_consume_amount double comment '前6天普通礼物打赏金额',
    before6d_normal_consume_order_cnt bigint comment '前6天普通礼物打赏次数',

    before13d_consume_amount double comment '前13天整体打赏金额',
    before13d_consume_order_cnt bigint comment '前13天整体打赏次数',
    before13d_ai_consume_amount double comment '前13天AI礼物打赏金额',
    before13d_ai_consume_order_cnt bigint comment '前13天AI礼物打赏次数',
    before13d_normal_consume_amount double comment '前13天普通礼物打赏金额',
    before13d_normal_consume_order_cnt bigint comment '前13天普通礼物打赏次数',

    before20d_consume_amount double comment '前20天整体打赏金额',
    before20d_consume_order_cnt bigint comment '前20天整体打赏次数',
    before20d_ai_consume_amount double comment '前20天AI礼物打赏金额',
    before20d_ai_consume_order_cnt bigint comment '前20天AI礼物打赏次数',
    before20d_normal_consume_amount double comment '前20天普通礼物打赏金额',
    before20d_normal_consume_order_cnt bigint comment '前20天普通礼物打赏次数',

    before6d_active_dcnt bigint comment '前6天有效活跃天数',
    before6d_watch_dcnt bigint comment '前6天观看天数',
    before6d_watch_duration double comment '前6天观看总时长，分钟',
    before6d_watch_anchorcnt bigint comment '前6天观看主播数',
    before6d_watch_gamecnt bigint comment '前6天观看品类数',

    before13d_active_dcnt bigint comment '前13天有效活跃天数',
    before13d_watch_dcnt bigint comment '前13天观看天数',
    before13d_watch_duration double comment '前13天观看总时长，分钟',
    before13d_watch_anchorcnt bigint comment '前13天观看主播数',
    before13d_watch_gamecnt bigint comment '前13天观看品类数',

    before20d_active_dcnt bigint comment '前20天有效活跃天数',
    before20d_watch_dcnt bigint comment '前20天观看天数',
    before20d_watch_duration double comment '前20天观看总时长，分钟',
    before20d_watch_anchorcnt bigint comment '前20天观看主播数',
    before20d_watch_gamecnt bigint comment '前20天观看品类数',

    before30d_active_dcnt bigint comment '前30天有效活跃天数',
    before30d_watch_dcnt bigint comment '前30天观看天数',
    before30d_watch_duration double comment '前30天观看总时长，分钟',
    before30d_watch_anchorcnt bigint comment '前30天观看主播数',
    before30d_watch_gamecnt bigint comment '前30天观看品类数',

    after6d_consume_amount double comment '后6天整体打赏金额',
    after6d_consume_order_cnt bigint comment '后6天整体打赏次数',
    after6d_ai_consume_amount double comment '后6天AI礼物打赏金额',
    after6d_ai_consume_order_cnt bigint comment '后6天AI礼物打赏次数',
    after6d_normal_consume_amount double comment '后6天普通礼物打赏金额',
    after6d_normal_consume_order_cnt bigint comment '后6天普通礼物打赏次数',

    after13d_consume_amount double comment '后13天整体打赏金额',
    after13d_consume_order_cnt bigint comment '后13天整体打赏次数',
    after13d_ai_consume_amount double comment '后13天AI礼物打赏金额',
    after13d_ai_consume_order_cnt bigint comment '后13天AI礼物打赏次数',
    after13d_normal_consume_amount double comment '后13天普通礼物打赏金额',
    after13d_normal_consume_order_cnt bigint comment '后13天普通礼物打赏次数',

    after20d_consume_amount double comment '后20天整体打赏金额',
    after20d_consume_order_cnt bigint comment '后20天整体打赏次数',
    after20d_ai_consume_amount double comment '后20天AI礼物打赏金额',
    after20d_ai_consume_order_cnt bigint comment '后20天AI礼物打赏次数',
    after20d_normal_consume_amount double comment '后20天普通礼物打赏金额',
    after20d_normal_consume_order_cnt bigint comment '后20天普通礼物打赏次数'
)
comment 'AI工坊PSM用户消费、活跃、观看前置特征及前后打赏拆解表 v2'
partitioned by (dt string comment 'cohort日期，即tdate')
stored as orc;

with item_dim as (
    select
        item_id,
        max(case when item_level = '礼物' and ext['is_ai'] = '1' then 1 else 0 end) as is_ai
    from gamelive.dim_huya_item_d_a
    where dt = '${tdate?string('yyyy-MM-dd')}'
    group by item_id
),

treatment_users as (
    -- 实验组：tdate当天被曝光且支付AI礼物
    select user_ukey, max(user_uid) as user_uid
    from zhgametemp.zty_ads_huya_ai_gift_user_detail_0901_v1
    where dt = '${tdate?string('yyyy-MM-dd')}'
      and user_ukey is not null
      and is_exposure = true
      and is_pay = true
    group by user_ukey
),

active_base_users as (
    -- 对照组候选池：tdate当天有效活跃用户，直接过滤活跃表分区
    select distinct user_ukey
    from gamelive.dws_huya_active_product_ukey_info_withsdk_d_i
    where dt = '${tdate?string('yyyy-MM-dd')}'
      and product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
      and is_black_ukey = 0
      and user_ukey is not null
),

ai_user_status as (
    -- 识别tdate当天是否出现过AI曝光或AI支付
    select
        user_ukey,
        max(case when is_exposure = true then 1 else 0 end) as has_exposure,
        max(case when is_pay = true then 1 else 0 end) as has_ai_pay
    from zhgametemp.zty_ads_huya_ai_gift_user_detail_0901_v1
    where dt = '${tdate?string('yyyy-MM-dd')}'
      and user_ukey is not null
    group by user_ukey
),

control_users as (
    -- 对照组：tdate当天活跃、未曝光、未支付AI礼物
    select a.user_ukey
    from active_base_users a
    left join ai_user_status b on a.user_ukey = b.user_ukey
    where coalesce(b.has_exposure, 0) = 0
      and coalesce(b.has_ai_pay, 0) = 0
),

user_info as (
    select user_uid, user_ukey, cast(1 as double) as is_treatment
    from treatment_users
    union all
    select cast(null as string), user_ukey, cast(0 as double)
    from control_users
),

consume_detail as (
    -- 消费表扫描tdate前30天至后20天，r.dt为分区字段
    select
        u.user_uid,
        u.user_ukey,
        u.is_treatment,
        r.dt,
        r.order_id,
        r.user_consume_amount,
        coalesce(i.is_ai, 0) as is_ai
    from user_info u
    inner join gamelive.dws_huya_revenue_detail_d_i r
        on r.ext['ukey'] = u.user_ukey
    left join item_dim i on r.item_id = i.item_id
    where r.dt between '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}'
                    and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}'
      and length(r.dt) = 10
      and r.consume_order_type = '礼物'
      and r.user_consume_amount > 0
      and r.order_id is not null
      and r.ext['ukey'] is not null
),

user_consume_panel as (
    -- 以用户池为主表保留无打赏用户；否则inner join会把对照组零消费用户丢掉
    select
        u.user_uid,
        u.user_ukey,
        u.is_treatment,
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

        sum(case when dt between '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as before6d_consume_amount,
        count(distinct case when dt between '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then order_id end) as before6d_consume_order_cnt,
        sum(case when is_ai=1 and dt between '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as before6d_ai_consume_amount,
        count(distinct case when is_ai=1 and dt between '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then order_id end) as before6d_ai_consume_order_cnt,
        sum(case when is_ai=0 and dt between '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as before6d_normal_consume_amount,
        count(distinct case when is_ai=0 and dt between '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then order_id end) as before6d_normal_consume_order_cnt,

        sum(case when dt between '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as before13d_consume_amount,
        count(distinct case when dt between '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then order_id end) as before13d_consume_order_cnt,
        sum(case when is_ai=1 and dt between '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as before13d_ai_consume_amount,
        count(distinct case when is_ai=1 and dt between '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then order_id end) as before13d_ai_consume_order_cnt,
        sum(case when is_ai=0 and dt between '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as before13d_normal_consume_amount,
        count(distinct case when is_ai=0 and dt between '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then order_id end) as before13d_normal_consume_order_cnt,

        sum(case when dt between '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as before20d_consume_amount,
        count(distinct case when dt between '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then order_id end) as before20d_consume_order_cnt,
        sum(case when is_ai=1 and dt between '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as before20d_ai_consume_amount,
        count(distinct case when is_ai=1 and dt between '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then order_id end) as before20d_ai_consume_order_cnt,
        sum(case when is_ai=0 and dt between '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as before20d_normal_consume_amount,
        count(distinct case when is_ai=0 and dt between '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then order_id end) as before20d_normal_consume_order_cnt,

        sum(case when dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as after6d_consume_amount,
        count(distinct case when dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}' then order_id end) as after6d_consume_order_cnt,
        sum(case when is_ai=1 and dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as after6d_ai_consume_amount,
        count(distinct case when is_ai=1 and dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}' then order_id end) as after6d_ai_consume_order_cnt,
        sum(case when is_ai=0 and dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as after6d_normal_consume_amount,
        count(distinct case when is_ai=0 and dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 6)?string('yyyy-MM-dd')}' then order_id end) as after6d_normal_consume_order_cnt,

        sum(case when dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as after13d_consume_amount,
        count(distinct case when dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}' then order_id end) as after13d_consume_order_cnt,
        sum(case when is_ai=1 and dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as after13d_ai_consume_amount,
        count(distinct case when is_ai=1 and dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}' then order_id end) as after13d_ai_consume_order_cnt,
        sum(case when is_ai=0 and dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as after13d_normal_consume_amount,
        count(distinct case when is_ai=0 and dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 13)?string('yyyy-MM-dd')}' then order_id end) as after13d_normal_consume_order_cnt,

        sum(case when dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as after20d_consume_amount,
        count(distinct case when dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}' then order_id end) as after20d_consume_order_cnt,
        sum(case when is_ai=1 and dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as after20d_ai_consume_amount,
        count(distinct case when is_ai=1 and dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}' then order_id end) as after20d_ai_consume_order_cnt,
        sum(case when is_ai=0 and dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}' then user_consume_amount else 0 end) as after20d_normal_consume_amount,
        count(distinct case when is_ai=0 and dt between '${DateUtils.addDays(tdate, 1)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, 20)?string('yyyy-MM-dd')}' then order_id end) as after20d_normal_consume_order_cnt
    from user_consume_panel
    group by user_uid, user_ukey, is_treatment
),

active_metrics as (
    -- 活跃特征：前6/13/20/30日有效活跃天数
    select
        u.user_ukey,
        count(distinct case when a.dt between '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then a.dt end) as before6d_active_dcnt,
        count(distinct case when a.dt between '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then a.dt end) as before13d_active_dcnt,
        count(distinct case when a.dt between '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then a.dt end) as before20d_active_dcnt,
        count(distinct case when a.dt between '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then a.dt end) as before30d_active_dcnt
    from user_info u
    inner join gamelive.dws_huya_active_product_ukey_info_withsdk_d_i a
        on a.user_ukey = u.user_ukey
    where a.dt between '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
      and a.product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
      and a.is_black_ukey = 0
      and a.user_ukey is not null
    group by u.user_ukey
),

watch_metrics as (
    -- 观看特征：user_duration按毫秒转分钟；窗口均为tdate之前，不使用后置行为
    select
        u.user_ukey,
        count(distinct case when w.dt between '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then w.dt end) as before6d_watch_dcnt,
        sum(case when w.dt between '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then coalesce(w.user_duration, 0) else 0 end) / 60000.0 as before6d_watch_duration,
        count(distinct case when w.dt between '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then w.luid end) as before6d_watch_anchorcnt,
        count(distinct case when w.dt between '${DateUtils.addDays(tdate, -6)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then w.sgamename end) as before6d_watch_gamecnt,

        count(distinct case when w.dt between '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then w.dt end) as before13d_watch_dcnt,
        sum(case when w.dt between '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then coalesce(w.user_duration, 0) else 0 end) / 60000.0 as before13d_watch_duration,
        count(distinct case when w.dt between '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then w.luid end) as before13d_watch_anchorcnt,
        count(distinct case when w.dt between '${DateUtils.addDays(tdate, -13)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then w.sgamename end) as before13d_watch_gamecnt,

        count(distinct case when w.dt between '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then w.dt end) as before20d_watch_dcnt,
        sum(case when w.dt between '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then coalesce(w.user_duration, 0) else 0 end) / 60000.0 as before20d_watch_duration,
        count(distinct case when w.dt between '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then w.luid end) as before20d_watch_anchorcnt,
        count(distinct case when w.dt between '${DateUtils.addDays(tdate, -20)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then w.sgamename end) as before20d_watch_gamecnt,

        count(distinct case when w.dt between '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then w.dt end) as before30d_watch_dcnt,
        sum(case when w.dt between '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then coalesce(w.user_duration, 0) else 0 end) / 60000.0 as before30d_watch_duration,
        count(distinct case when w.dt between '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then w.luid end) as before30d_watch_anchorcnt,
        count(distinct case when w.dt between '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}' then w.sgamename end) as before30d_watch_gamecnt
    from user_info u
    inner join gamelive.dwt_huya_ayyuid_session_from_server_with_user w
        on w.user_ukey = u.user_ukey
    where w.dt between '${DateUtils.addDays(tdate, -30)?string('yyyy-MM-dd')}' and '${DateUtils.addDays(tdate, -1)?string('yyyy-MM-dd')}'
      and w.tag = 'gameid'
      and w.htime = 'session'
      and w.user_product in ('huya_andriod', 'huya_ipad', 'huya_pad', 'huya_ios')
      and w.user_ukey is not null
      and w.luid is not null
    group by u.user_ukey
),

all_metrics as (
    select
        c.*,
        coalesce(a.before6d_active_dcnt, 0) as before6d_active_dcnt,
        coalesce(a.before13d_active_dcnt, 0) as before13d_active_dcnt,
        coalesce(a.before20d_active_dcnt, 0) as before20d_active_dcnt,
        coalesce(a.before30d_active_dcnt, 0) as before30d_active_dcnt,
        coalesce(w.before6d_watch_dcnt, 0) as before6d_watch_dcnt,
        coalesce(w.before6d_watch_duration, 0.0) as before6d_watch_duration,
        coalesce(w.before6d_watch_anchorcnt, 0) as before6d_watch_anchorcnt,
        coalesce(w.before6d_watch_gamecnt, 0) as before6d_watch_gamecnt,
        coalesce(w.before13d_watch_dcnt, 0) as before13d_watch_dcnt,
        coalesce(w.before13d_watch_duration, 0.0) as before13d_watch_duration,
        coalesce(w.before13d_watch_anchorcnt, 0) as before13d_watch_anchorcnt,
        coalesce(w.before13d_watch_gamecnt, 0) as before13d_watch_gamecnt,
        coalesce(w.before20d_watch_dcnt, 0) as before20d_watch_dcnt,
        coalesce(w.before20d_watch_duration, 0.0) as before20d_watch_duration,
        coalesce(w.before20d_watch_anchorcnt, 0) as before20d_watch_anchorcnt,
        coalesce(w.before20d_watch_gamecnt, 0) as before20d_watch_gamecnt,
        coalesce(w.before30d_watch_dcnt, 0) as before30d_watch_dcnt,
        coalesce(w.before30d_watch_duration, 0.0) as before30d_watch_duration,
        coalesce(w.before30d_watch_anchorcnt, 0) as before30d_watch_anchorcnt,
        coalesce(w.before30d_watch_gamecnt, 0) as before30d_watch_gamecnt
    from consume_metrics c
    left join active_metrics a on c.user_ukey = a.user_ukey
    left join watch_metrics w on c.user_ukey = w.user_ukey
)

insert overwrite table zhgametemp.zty_ai_gift_psm_user_revenue_breakdown_v2
partition (dt = '${tdate?string('yyyy-MM-dd')}')
select
    user_uid,
    user_ukey,
    is_treatment,

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
    coalesce(after20d_normal_consume_order_cnt, 0)
from all_metrics;
