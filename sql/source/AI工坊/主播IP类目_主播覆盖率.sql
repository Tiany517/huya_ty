-- ============================================================
-- 主播IP 类目的「主播覆盖率」
-- 问题：主播IP 类目流水占比 48%，但它到底覆盖了多少主播？
-- 时间窗：2026-07-13 ~ 2026-09-14
-- 分母口径给了三个（一次扫描同时算出）：
--   all    = 时间窗内被打赏过任意礼物的主播
--   normal = 时间窗内被打赏过普通礼物（非 AI 礼物）的主播
--   ge52   = 时间窗内累计被打赏金额 >= 52 元的主播（对齐 AI 礼物最低价档）
-- 注意事项：
--   1) 标签表已有 primary_anchor_id（就是 dim_huya_ayyuid_info.uid），
--      不要再按 primary_anchor_name = nick 关联，昵称会重名/改名，会把行数放大。
--      本次交付的标签表 primary_anchor_id 无空值，可以放心直接当 uid 用。
--   2) 「普通礼物」= 不在 AI 礼物清单里的礼物，AI 礼物清单直接取标签表的 item_id 全集，
--      比再回 gamelive.dim_huya_item_d_a 关联 ext['is_ai'] 便宜得多。
--   3) 分子是「主播IP 礼物的归属主播」，即标签表里该礼物金额最集中的那个主播；
--      若要严格到「实际收到主播IP礼物的主播」，需把标签表 item_id 回连 revenue 明细，
--      当前这份表已带上 primary_anchor_id，直接可用。
-- ============================================================
with
-- t1：主播IP 类目覆盖到的归属主播（uid 直接取标签表）
t1 as (
    select distinct
        cast(a.primary_anchor_id as bigint) as creator_uid
    from zhgametemp.zty_sold_gift_item_with_label_v5 a
    where a.category_l1 = '主播IP'
      and a.primary_anchor_id is not null
      and cast(a.sales_amount as double) > 0
),

-- t2：时间窗内每个被打赏主播的汇总，一次扫描同时得到三个分母
t2 as (
    select
        r.creator_uid
        ,sum(cast(r.user_consume_amount as double))            as consume_amount
        ,max(case when ai.item_id is null then 1 else 0 end)   as has_normal_gift
    from gamelive.dws_huya_revenue_detail_d_i r
    left join (
        select distinct cast(x.item_id as varchar) as item_id
        from zhgametemp.zty_sold_gift_item_with_label_v5 x
    ) ai
        on cast(r.item_id as varchar) = ai.item_id
    where r.dt between '2026-07-13' and '2026-09-14'
      and r.consume_order_type = '礼物'
      and cast(r.user_consume_amount as double) > 0
      and r.user_uid is not null
      and lower(cast(r.user_uid as varchar)) not in ('0', 'other')
      and r.ext['ukey'] is not null
      and lower(cast(element_at(r.ext, 'ukey') as varchar)) not in ('', '0', 'other')
      and r.creator_uid is not null
    group by r.creator_uid
)

select
    count(distinct t2.creator_uid)                                            as gift_anchor_cnt
    ,sum(case when t2.has_normal_gift = 1 then 1 else 0 end)                   as normal_gift_anchor_cnt
    ,sum(case when t2.consume_amount >= 52 then 1 else 0 end)                  as ge52_anchor_cnt
    ,count(distinct case when t1.creator_uid is not null then t2.creator_uid end)
                                                                              as ip_anchor_covered_cnt
    ,cast(count(distinct case when t1.creator_uid is not null then t2.creator_uid end) as double)
        / count(distinct t2.creator_uid)                                       as ip_coverage_rate_all
    ,cast(count(distinct case when t1.creator_uid is not null and t2.has_normal_gift = 1 then t2.creator_uid end) as double)
        / sum(case when t2.has_normal_gift = 1 then 1 else 0 end)              as ip_coverage_rate_normal
    ,cast(count(distinct case when t1.creator_uid is not null and t2.consume_amount >= 52 then t2.creator_uid end) as double)
        / sum(case when t2.consume_amount >= 52 then 1 else 0 end)             as ip_coverage_rate_ge52
from t2
left join t1
    on t1.creator_uid = t2.creator_uid
;

-- ============================================================
-- 补充口径A：品内覆盖率（只用标签表，秒出，建议先看这个）
--   分母 = 全部 AI 礼物覆盖到的归属主播数
--   分子 = 主播IP 覆盖到的归属主播数
--   预期值：分子 173，分母 314，覆盖率 55.10%
-- ============================================================
select
    count(distinct case when category_l1 = '主播IP' then primary_anchor_id end)
                                                              as ip_anchor_cnt
    ,count(distinct primary_anchor_id)                        as ai_anchor_cnt
    ,cast(count(distinct case when category_l1 = '主播IP' then primary_anchor_id end) as double)
        / count(distinct primary_anchor_id)                   as ip_coverage_rate_within_ai
from zhgametemp.zty_sold_gift_item_with_label_v5
;

-- ============================================================
-- 补充口径B：主播IP 二级类目各自的覆盖主播数（看结构用）
--   预期：主播热梗 81 / 主播肖像 134 / 公会肖像 25 / 网友热梗 24
-- ============================================================
select
    category_l2
    ,count(distinct primary_anchor_id) as anchor_cnt
    ,count(1)                          as item_cnt
    ,sum(cast(sales_amount as double)) as sales_amount
from zhgametemp.zty_sold_gift_item_with_label_v5
where category_l1 = '主播IP'
group by category_l2
order by sales_amount desc
;
