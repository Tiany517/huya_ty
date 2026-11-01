-- =====================================================================
-- 目的：站外（竞品反挖预测）+ 站内（虎牙实际表现）合并成一张表，
--       并在「每月 × 整个品类」内按有效 ACU 排出 rnk
-- 时间：2026-01 ~ 2026-09，逐月输出（站外取 1-9 月月报；站内取 2026-01-01 ~ 2026-09-30）
-- 粒度：month + pcode + r_lid + r_category（一行 = 一个主播的一个月）
-- 口径：zhanwai 完全保持原样；站内字段名、列顺序向 zhanwai 看齐
--       live_days = 该月有开播记录的天数（count(distinct dt)），站内外同口径
--       actual_view_mins = 该月实际观时（分钟），站内外都用实际值：
--           站外 = zhgametemp.yty_jingpin_anchor_vaild_dau.watch_min（原口径即分钟，日数据 by月 sum）
--           站内 = gamelive.dwt_huya_ayyuid_session_from_server_with_user.user_duration（毫秒 ÷ 60000）
-- =====================================================================
with

-- 0) 站外开播天数：竞品主播日表按「月 × 平台 × 品类 × 主播」数天数
zhanwai_live_days as (
    select
        substr(cast(d.dt as varchar),1,7) as month
        ,d.pcode
        ,d.r_category
        ,cast(d.r_lid as varchar) as r_lid
        ,count(distinct substr(cast(d.dt as varchar),1,10)) as live_days
    from gamelive.dm_mkt_rowner_day d
    where d.dt between '2026-01-01' and '2026-09-30'
      and d.r_category in ('无畏契约')
      -- 如需只算「有效开播日」（当天有效 ACU > 0），加下面这行
      -- and cast(regexp_extract(d.ext['vaild_acu'], '([0-9]+)', 1) as bigint) > 0
    group by
        substr(cast(d.dt as varchar),1,7)
        ,d.pcode
        ,d.r_category
        ,cast(d.r_lid as varchar)
),

-- 0-b) 站外实际观时（逐月）：竞品主播日表，watch_min 原口径就是分钟，
--      该表每天一行，按月 sum 得当月总观时（分钟）
--      粒度：月 + pcode + r_category + r_lid
zhanwai_actual as (
    select
        substr(cast(a.dt as varchar),1,7) as month
        ,a.pcode
        ,a.r_category
        ,cast(a.r_lid as varchar) as r_lid
        ,sum(a.watch_min) as actual_view_mins
    from zhgametemp.yty_jingpin_anchor_vaild_dau a
    where a.dt between '2026-01-01' and '2026-09-30'
      and a.r_category in ('无畏契约')
      and a.watch_min is not null
    group by
        substr(cast(a.dt as varchar),1,7)
        ,a.pcode
        ,a.r_category
        ,cast(a.r_lid as varchar)
),

-- =========================== 站外（口径不变，放开到逐月） ===========================
zhanwai as (
    select
        substr(t1.dt,1,7) as month
        ,t1.dt
        ,t1.pcode
        ,t1.r_owner
        ,t1.r_lid
        ,t1.r_category
        ,t1.cate1
        ,round(t1.juhe_vaild_acu,0) as juhe_vaild_acu
        ,ld.live_days
        -- ,round(t2.danmu,0) as danmu
        -- ,round(t2.dingyue_add,0) as dingyue_add
        -- ,round(t2.dingyue_all,0) as dingyue_all
        ,t2.live_mins
        ,wa.actual_view_mins                    -- 站外实际观时（分钟）
        ,t2.gift_user
        ,t2.gift_value
        ,t2.predict_acu
        ,t2.predict_viewhours
        ,t2.predict_laxin
        ,t2.predict_yingshou
        ,t2.predict_pay_year
    from gamelive.ads_huya_jingpin_shuangbo_anchor_rpt_m_i t1
    join (
        select
            dt
            ,pcode
            ,r_owner
            ,uid
            ,r_category
            -- ,danmu
            -- ,dingyue_add
            -- ,dingyue_all
            ,live_mins
            ,gift_user
            ,gift_value
            ,predict_acu
            ,predict_viewhours
            ,predict_laxin
            ,predict_yingshou
            ,predict_pay_year
        from zhgametemp.cys_huya_jingpin_fanwa_result
        where substr(dt,1,7) between '2026-01' and '2026-09' and r_category in ('无畏契约')
    ) t2
      on t1.pcode = t2.pcode
     and t1.r_lid = t2.uid
     and t1.r_category = t2.r_category
     and substr(t1.dt,1,7) = substr(t2.dt,1,7)
    left join zhanwai_live_days ld
      on substr(t1.dt,1,7) = ld.month
     and t1.pcode = ld.pcode
     and t1.r_category = ld.r_category
     and cast(t1.r_lid as varchar) = ld.r_lid
    left join zhanwai_actual wa
      on substr(t1.dt,1,7) = wa.month
     and t1.pcode = wa.pcode
     and t1.r_category = wa.r_category
     and cast(t1.r_lid as varchar) = wa.r_lid
    where substr(t1.dt,1,7) between '2026-01' and '2026-09'
      and t1.juhe_vaild_acu <> 0
      and t1.r_category in (
        '无畏契约'
      )
),

-- 1) 主播日明细：分区时间 + 业务条件先行过滤，只保留当天真的开播
--    粒度：month + dt + luid；acu 正常一天一行，sum 即原值
anchor_day as (
    select
        substr(cast(dt as varchar),1,7) as month
        ,substr(cast(dt as varchar),1,10) as dt
        ,cast(ayyuid as varchar) as luid
        ,max(nickname) as nickname
        ,sum(acu) as acu
        ,sum(live_hours_only_live) as live_hours
    from gamelive.dm_huya_ayyuid_detail_day
    where dt between '2026-01-01' and '2026-09-30'
      and gameid = 5937
      and live_hours_only_live > 0
    group by
        substr(cast(dt as varchar),1,7)
        ,substr(cast(dt as varchar),1,10)
        ,cast(ayyuid as varchar)
),

-- 2) 主播月度：开播天数 = 当月有开播记录的天数（即有效 ACU 的分母）
--    有效 ACU 取「当月日均」；直播时长取「当月汇总」，live_hours_only_live 单位是小时，×60 转分钟
--    昵称取当月最后一次开播日的昵称
anchor_month as (
    select
        month
        ,luid
        ,max_by(nickname, dt) as nickname
        ,count(distinct dt) as live_days
        ,avg(acu) as acu_avg_day
        ,sum(live_hours) * 60 as live_mins
    from anchor_day
    group by
        month
        ,luid
),

-- 3) 站内实际观时（逐月）：server 观看会话表
--    来源：gamelive.dwt_huya_ayyuid_session_from_server_with_user
--    tag = 'gameid'、htime = 'session' 为固定写法；igameid 限无畏契约 5937（与站内品类口径一致）
--    user_duration 单位毫秒，/60000.0 转分钟
view_month as (
    select
        substr(cast(v.dt as varchar),1,7) as month
        ,cast(v.luid as varchar) as luid
        ,sum(v.user_duration) / 60000.0 as actual_view_mins
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user v
    where v.dt between '2026-01-01' and '2026-09-30'
      and v.tag = 'gameid'
      and v.htime = 'session'
      and v.igameid = 5937
      and v.user_product in ('huya_flashexternal','huya_flash','huyawap','huya_web')  -- web端
      and v.user_duration > 0
      and v.user_ukey is not null
    group by
        substr(cast(v.dt as varchar),1,7)
        ,cast(v.luid as varchar)
),

-- -- 4) 弹幕（逐月）：只统计上面那批有效开播日（dt + 主播）当天的有效弹幕（passed = '0'），按月汇总条数
-- danmu_month as (
--     select
--         a.month
--         ,a.luid
--         ,count(*) as danmu
--     from gamelive.gamelive_huya_danmu_log d
--     inner join anchor_day a
--       on substr(cast(d.dt as varchar),1,10) = a.dt
--      and cast(d.lpid as varchar) = a.luid
--     where d.dt between '2026-01-01' and '2026-09-30'
--       and d.passed = '0'
--       and d.lpid is not null
--       and d.time is not null
--     group by a.month, a.luid
-- ),

-- 5) 打赏（剔除刷单表）：按月汇总的打赏人数 + 打赏流水
--    人数取 ext['ukey'] 去重，金额取 user_consume_amount（实际成交金额）
revenue_month as (
    select
        substr(cast(r.dt as varchar),1,7) as month
        ,cast(r.user_uid as varchar) as luid
        ,count(distinct r.ext['ukey']) as gift_user
        ,sum(cast(r.user_consume_amount as double)) as gift_value
    from gamelive.dws_huya_revenue_detail_d_i  r
    where r.dt between '2026-01-01' and '2026-09-30'
      -- and r.game_id = 5937
      and cast(r.user_consume_amount as double) > 0
      and r.ext['ukey'] is not null
    group by
        substr(cast(r.dt as varchar),1,7)
        ,cast(r.user_uid as varchar)
),

-- -- 6) 订阅（逐月）：dwd_huya_dy_user 是「每日全量订阅关系快照」
-- --    累计订阅 = 该月最后一次快照人数；新增订阅 = 本月 − 上月（净增，含取关，可能为负）
-- dy_day as (
--     select
--         substr(s.dt,1,10) as dt
--         ,cast(s.ayyuid as varchar) as luid
--         ,count(distinct s.yyuid) as dy_cnt
--     from gamelive.dwd_huya_dy_user s
--     where substr(s.dt,1,10) between '2025-12-31' and '2026-09-30'
--       and s.tag = 'huya'
--       and length(s.dt) = 10
--       and s.yyuid is not null
--     group by
--         substr(s.dt,1,10)
--         ,cast(s.ayyuid as varchar)
-- ),
-- dy_month as (
--     select
--         month
--         ,luid
--         ,dingyue_all
--         ,dingyue_all - coalesce(lag(dingyue_all) over (partition by luid order by month), 0) as dingyue_add
--     from (
--         select
--             substr(dt,1,7) as month
--             ,luid
--             ,max_by(dy_cnt, dt) as dingyue_all
--         from dy_day
--         group by substr(dt,1,7), luid
--     ) t
-- ),

-- 7) 站内拼装：列名与列顺序严格对齐 zhanwai
--    站内没有预测模型，predict_* 填 null；实际值走 juhe_vaild_acu / actual_view_mins
zhannei as (
    select
        m.month
        ,cast(last_day_of_month(date(concat(m.month,'-01'))) as varchar) as dt   -- 该月月末日期，与站外月报快照日对齐
        ,'huya' as pcode
        ,cast(m.nickname as varchar) as r_owner          -- 站内无竞品运营归属
        ,m.luid as r_lid
        ,'无畏契约' as r_category                  -- gameid 5937
        ,'无畏契约' as cate1
        ,round(m.acu_avg_day,0) as juhe_vaild_acu  -- 当月日均 ACU（分母 = 当月开播天数）
        ,m.live_days                               -- 当月开播天数
        -- ,round(cast(coalesce(dm.danmu,0) as double),0) as danmu
        -- ,round(cast(coalesce(dy.dingyue_add,0) as double),0) as dingyue_add
        -- ,round(cast(coalesce(dy.dingyue_all,0) as double),0) as dingyue_all
        ,m.live_mins
        ,coalesce(vw.actual_view_mins, 0) as actual_view_mins   
        ,coalesce(rv.gift_user,0) as gift_user
        ,coalesce(rv.gift_value,0) as gift_value
        ,round(null,0) as predict_acu      
        ,cast(null as double) as predict_viewhours          -- 站内无预测模型；实际观时见 actual_view_mins
        ,cast(null as double) as predict_laxin
        ,coalesce(rv.gift_value,0) as predict_yingshou 
        ,cast(null as double) as predict_pay_year
    from anchor_month m
    -- left join danmu_month dm
    --   on m.month = dm.month
    --  and m.luid = dm.luid
    -- left join dy_month dy
    --   on m.month = dy.month
    --  and m.luid = dy.luid
    left join revenue_month rv
      on m.month = rv.month
     and m.luid = rv.luid
    left join view_month vw
      on m.month = vw.month
     and m.luid = vw.luid
),

-- =========================== 站内外合并 ===========================
all_anchor as (
    select * from zhanwai
    union all
    select * from zhannei
)

-- 主查询：逐月、站内外同一个品类内按有效 ACU 排序形成 rnk
select
    month
    ,dt
    ,pcode
    ,r_owner
    ,r_lid
    ,r_category
    ,cate1
    ,juhe_vaild_acu
    ,live_days
    ,live_mins
    ,actual_view_mins
    ,gift_user
    ,gift_value
    ,predict_acu
    ,predict_viewhours
    ,predict_laxin
    ,predict_yingshou
    ,predict_pay_year
    ,row_number() over (partition by month, r_category order by juhe_vaild_acu desc) as rnk
from all_anchor
order by r_category, month, rnk