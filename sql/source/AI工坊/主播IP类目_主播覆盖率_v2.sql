-- ============================================================
-- 主播IP 类目的「主播覆盖率」= 覆盖的主主播数 / 总被打赏主播数
-- 时间窗：2026-07-13 ~ 2026-09-14
-- 分子：标签表 category_l1='主播IP' 的行，取 t1.uid（按 primary_anchor_name = nick 关联得到）
-- 分母：时间窗内被打赏过礼物的主播全集（dws_huya_revenue_detail_d_i.creator_uid）
-- 说明：t1 按用户要求保留 primary_anchor_name = nick 的关联方式，用 b.uid 作为主播身份。
--       两个主播身份字段的差异可用文件末尾的诊断语句量化（t1.uid 是否有空值、昵称是否放大行数）。
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

t2 as (
  select distinct
    r.creator_uid
  from gamelive.dws_huya_revenue_detail_d_i r
  where r.dt between '2026-07-13' and '2026-09-14'
    and r.consume_order_type = '礼物'
    and cast(r.user_consume_amount as double) > 0
    and r.user_uid is not null
    and lower(cast(r.user_uid as varchar)) not in ('0', 'other')
    and r.ext['ukey'] is not null
    and lower(cast(element_at(r.ext, 'ukey') as varchar)) not in ('', '0', 'other')
    and r.creator_uid is not null
)

select
  count(distinct t2.creator_uid)                                                    as anchor_cnt_total
  ,count(distinct case when t1.category_l1 = '主播IP' then t1.uid end)               as anchor_cnt_ip_covered
  ,cast(count(distinct case when t1.category_l1 = '主播IP' then t1.uid end) as double)
    / count(distinct t2.creator_uid)                                                 as ip_anchor_coverage_rate
from t2
left join t1
  on t1.uid = t2.creator_uid
;

-- ============================================================
-- 诊断（单独跑，不扫明细表，很快）：看昵称关联这一步的质量
--   label_row_cnt         标签表行数，应为 5551
--   nick_matched_uid_cnt  关联上的 uid 数
--   uid_null_row_cnt      昵称没匹配上 uid 的行数（这些行进不了分子）
--   row_inflated_cnt      被昵称一对多放大的行数（行数 - 去重礼物ID数）
--   id_vs_uid_mismatch    关联到的 uid 与表里 primary_anchor_id 不一致的行数
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
)

select
  count(1)                                          as label_row_cnt
  ,count(distinct item_id)                          as label_item_cnt
  ,count(distinct uid)                              as nick_matched_uid_cnt
  ,sum(case when uid is null then 1 else 0 end)     as uid_null_row_cnt
  ,count(distinct case when uid is null then item_id end) as uid_null_item_cnt
  ,count(1) - count(distinct item_id)               as row_inflated_cnt
  ,sum(case when uid is not null and cast(uid as bigint) <> cast(primary_anchor_id as bigint) then 1 else 0 end)
                                                    as id_vs_uid_mismatch
from t1
;
