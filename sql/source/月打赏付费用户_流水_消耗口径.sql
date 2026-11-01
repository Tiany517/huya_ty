select substr(dt,1,7) mth,sum(peiwan_amt) peiwan_amt,sum(zhibo_pay_amt_without_qd) zhibo_pay_amt_without_qd,sum(zhibo_pay_amt) zhibo_pay_amt
,count(distinct case when (peiwan_amt>0 or zhibo_pay_amt>0) then user_uid else null end) pay_uv,
count(distinct case when (peiwan_amt>0 or zhibo_pay_amt_without_qd>0) then user_uid else null end) pay_uv_withoutqu,
count(distinct case when peiwan_amt>0 then user_uid else null end) peiwan_uv,
count(distinct case when zhibo_pay_amt>0 then user_uid else null end) dashang_uv,
count(distinct case when zhibo_pay_amt_without_qd>0 then user_uid else null end) dashang_withoutqd_uv
from 
(
select dt,user_uid,
  sum(case when  consume_order_type='陪玩' and peiwan_consume_cnt>0 then peiwan_consume_amount else 0 end)
  peiwan_amt,
  sum(case when user_consume_amount>0 then user_consume_amount else 0 end) zhibo_pay_amt,
 sum(case when (user_consume_amount>0 and not (item_id  in ('20859','21155')  and game_id in (4079,7785)) )then user_consume_amount else 0 end) zhibo_pay_amt_without_qd
  from gamelive.dws_huya_revenue_detail_d_i
  where dt>='2026-05-01' and dt<='2026-06-30'
  and (user_consume_amount>0 or (consume_order_type='陪玩' and peiwan_consume_amount>0))
  --and not (item_id  in ('20859','21155')  and game_id in (4079,7785))
  group by dt,user_uid
)a 
group by substr(dt,1,7)