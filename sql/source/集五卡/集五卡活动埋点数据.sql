select 
    dt
    ,eventid
    ,'all' as array_except
    ,count(distinct ukey) as uv
    ,sum(1) as pv
from gamelive.dwd_huya_event 
where  
    dt between '2026-06-26' and '2026-06-28'
    and eventid in('show/first_lottery_popup') ---首抽弹窗曝光
    and product ='huya_hd'
group by 
    dt,eventid

union all 

select 
    dt
    ,eventid
    ,coalesce(get_json_object(ext['prop'],'$.area'),get_json_object(regexp_replace(ext['extra'], '\\]|\\[',''),'$.area')) as area
    ,count(distinct ukey) as uv
    ,sum(1) as pv
from gamelive.dwd_huya_event 
where 
    dt between '2026-06-26' and '2026-06-28'
    and eventid in('click/jwk_activity_button') ---点击/集五卡活动卡片
    and product ='huya_hd'
group by 
    dt
    ,coalesce(get_json_object(ext['prop'],'$.area'),get_json_object(regexp_replace(ext['extra'], '\\]|\\[',''),'$.area'))

union all 

select 
    dt
    ,eventid
    ,'all' as area
    ,count(distinct ukey) as uv
    ,sum(1) as pv
from gamelive.dwd_huya_event 
where 
    dt between '2026-06-26' and '2026-06-28'
    and eventid in('click/jwk_activity_button') ---点击/集五卡活动卡片
    and product ='huya_hd'
group by 
    dt
    ,coalesce(get_json_object(ext['prop'],'$.area'),get_json_object(regexp_replace(ext['extra'], '\\]|\\[',''),'$.area'))

union all 

select 
    dt
    ,eventid
    ,'all' as area
    ,count(distinct ukey) as uv
    ,sum(1) as pv
from gamelive.dwd_huya_event 
where 
    dt between '2026-06-26' and '2026-06-28'
    and eventid in('pageview/page') ---点击/集五卡活动卡片
    and product ='huya_hd'
group by 
    dt
    ,coalesce(get_json_object(ext['prop'],'$.area'),get_json_object(regexp_replace(ext['extra'], '\\]|\\[',''),'$.area'))