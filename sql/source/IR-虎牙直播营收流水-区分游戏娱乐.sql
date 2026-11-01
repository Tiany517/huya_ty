select substr(dt,1,7) mth,game_label,sum(peiwan_amt) peiwan_amt,sum(zhibo_pay_amt) zhibo_pay_amt,sum(peiwan_consume)
from 
(
select dt,user_uid,game_label,game_id,
  sum(case when  consume_order_type='陪玩' and peiwan_consume_cnt>0 then peiwan_consume_amount else 0 end)
  peiwan_amt,
  sum( peiwan_user_consume_amount) peiwan_consume,
  sum(case when user_consume_amount>0 then user_consume_amount else 0 end) zhibo_pay_amt
 --sum(case when (user_consume_amount>0 and not (item_id  in ('20859','21155')  and game_id in (4079,7785)) )then user_consume_amount else 0 end) zhibo_pay_amt_without_qd
  from gamelive.dws_huya_revenue_detail_d_i
  where dt>='2025-10-01' 
  --and dt<='2025-09-09'
  and (user_consume_amount>0 or (consume_order_type='陪玩' and peiwan_consume_amount>0))
  --and not (item_id  in ('20859','21155')  and game_id in (4079,7785))
  --and game_label='游戏'
  --and 
  group by dt,user_uid,game_label,game_id

)a 
group by substr(dt,1,7),game_label