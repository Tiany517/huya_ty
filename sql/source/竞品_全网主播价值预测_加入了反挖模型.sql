select 
   t1.dt
  ,t1.pcode
  ,t1.r_owner
  ,t1.r_lid
  ,t1.r_category
  ,t1.cate1
  ,round(t1.juhe_vaild_acu,0) as juhe_vaild_acu
  ,round(t2.danmu,0) as danmu
  ,round(t2.dingyue_add,0) as dingyue_add
  ,round(t2.dingyue_all,0) as dingyue_all
  ,t2.live_mins
  ,t2.gift_user
  ,t2.gift_value
  ,t2.predict_acu
  ,t2.predict_viewhours
  ,t2.predict_laxin
  ,t2.predict_yingshou
  ,t2.predict_pay_year
  ,row_number()over (partition by t1.dt,t1.cate1 order by t2.predict_acu desc) as rk
from gamelive.ads_huya_jingpin_shuangbo_anchor_rpt_m_i t1
join (
    select 
      dt
      ,pcode
      ,r_owner
      ,uid
      ,r_category
      ,danmu
      ,dingyue_add
      ,dingyue_all
      ,live_mins
      ,gift_user
      ,gift_value
      ,predict_acu
      ,predict_viewhours
      ,predict_laxin
      ,predict_yingshou,predict_pay_year
    from zhgametemp.cys_huya_jingpin_fanwa_result
    where substr(dt,1,7) =  '2026-09'---dt = cast(last_day_of_month(current_date - interval '1' month) as varchar)
) t2 
on 
    t1.pcode = t2.pcode 
    and t1.r_lid = t2.uid 
    and t1.r_category = t2.r_category 
    and substr(t1.dt,1,7)=substr(t2.dt,1,7)
where 
    substr(t1.dt,1,7) = '2026-09'
    and t1.juhe_vaild_acu <> 0
    and lower(t1.r_owner) like ('%hanghang%')
order by rk