-- 独立复算：直接在源事件表按行为、端count distinct，不复用主查询的user_flags。
select eventid,coalesce(product,'ALL_APP') product,
 count(*) event_rows,
 count(distinct case when yyuid is not null and trim(yyuid) not in ('','0','-1') then yyuid end) uid_uv,
 count(distinct case when yyuid is not null and trim(yyuid) not in ('','0','-1') and stime>='2026-11-12 00:00:00' and stime<'2026-11-13 00:00:00' then yyuid end) same_day_uid_uv,
 sum(case when yyuid is null or trim(yyuid) in ('','0','-1') then 1 else 0 end) invalid_uid_rows,
 sum(case when stime is null or stime<'2026-11-12 00:00:00' or stime>='2026-11-13 00:00:00' then 1 else 0 end) out_of_day_rows,
 min(stime) min_stime,max(stime) max_stime,count(distinct thour) hour_cnt
from gamelive.dwd_huya_event
where dt='2026-11-12' and ety='custom_event'
 and product in ('huya_andriod','huya_ios','huya_ipad','huya_pad','hmos_kiwi')
 and eventid in ('pageview/liveroom','click/verticallive/fullscreen')
group by grouping sets ((eventid,product),(eventid))
order by eventid,product
