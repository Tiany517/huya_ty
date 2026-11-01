-- ============================================================
-- 主播IP 类目：每个主播内部，二级类目（主播肖像/主播热梗/公会肖像/网友热梗）的流水结构
-- 时间窗：2026-07-13 ~ 2026-09-14（标签表自带该窗口）
-- 口径：ratio = 该主播某二级类目流水 / 该主播主播IP总流水（partition by nick）
-- 说明：窗口函数必须放在聚合之后，不能在同一个 select 里和 group by 混用，
--       所以先把 (nick, category_l2) 聚合好，外层再开窗。
-- ============================================================
with t1 as (
  select
    a.*,
    b.uid
  from zhgametemp.zty_sold_gift_item_with_label_v5 a
  left join (
    select uid,nick,roomid
    from gamelive.dim_huya_ayyuid_info
    where dt ='2026-09-15'
  ) b
  on a.primary_anchor_name = b.nick
),

-- 第一层：先聚合到 主播 x 二级类目
t2 as (
  select
    primary_anchor_name              as nick
    ,category_l2
    ,sum(cast(sales_amount as double)) as sales_amount
  from t1
  where category_l1 = '主播IP'
  group by
    primary_anchor_name
    ,category_l2
)

-- 第二层：外层开窗，算该主播的主播IP总流水
select
  nick
  ,category_l2
  ,sales_amount
  ,sum(sales_amount) over (partition by nick)                    as total_sales_amount
  ,sales_amount / sum(sales_amount) over (partition by nick)     as ratio
from t2
order by
  total_sales_amount desc
  ,nick
  ,ratio desc
;

-- ============================================================
-- 变体：如果 ratio 想表达「该主播占主播IP总流水的比重」（找出大客户），
-- 就把开窗的 partition by nick 去掉，改成 partition by ()：
--   sales_amount / sum(sales_amount) over () as ratio_of_ip_total
-- ============================================================
