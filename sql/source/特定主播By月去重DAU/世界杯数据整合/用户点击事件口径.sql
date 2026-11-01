with actual_new_user as (
    select 
        json_extract_scalar(ext['prop'], '$.source') AS source,
        count(1) as cnt,
        count(distinct ukey) as uv,
        count(distinct yyuid) as uv2
    from gamelive.dwd_huya_event 
    where dt between'2026-06-12' and '2026-06-30'
        and ety='custom_event'
        and eventid='usr/click/search' 
        and product in ('huya_andriod','huya_ipad','huya_pad','huya_ios','hmos_kiwi') --APP端
        and json_extract_scalar(ext['prop'], '$.keyword') like '%世界杯%'
    group by json_extract_scalar(ext['prop'], '$.source')
)