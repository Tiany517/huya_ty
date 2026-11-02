--月报
select a1.dt
,if(c1.online_duration_huya is null, '单播', '双播') as luid_type
,count(distinct userid) as luid_num--主播数
,avg(online_duration) as online_duration--开播时长
,sum(dau) as dau--总DAU
,sum(dau)*0.26 as dau_youxiao --总有效DAU，系数0.26 
from (
  select dt,userid,creator_uid,sum(cast(audiencecnt as bigint)) as dau,sum(cast(onlinetimeduration as double)) as online_duration,sum(cast(liveroomrewardcnt as double)) as liushui
  ,sum(cast(anchorrewardincome as double)) as anchor_reward_income,sum(cast(findertotalincome as double)) as shouru
  from  gamelive.dwd_spider_wxmcn_anchor_livedata_list_d_i a
  left join (
    select pid as creator_uid    ---主播uid
            ,vx_vedio_id           ---微信视频号
    from  gamelive.ods_live_huya_vedio_stream_push_conf_1760614652931321858
    where dt = date_add(cast(current_date as varchar), -1) --取最新日期
    group by pid,vx_vedio_id 
  ) b on a.userid = b.vx_vedio_id
  where a.dt>='2026-05-25' and a.dt <= '2026-06-14'
  and cast(onlinetimeduration as double) > 0 -- 开播 
  group by dt,userid,creator_uid
) a1
left join (
   select dt, luid, sum(cast(online_duration as double)/1000/3600) as online_duration_huya
   from gamelive.dwt_huya_ayyuid_session_from_server_no_user          
   where dt>='2026-05-25' and dt <= '2026-06-14'
   and length(dt)=10          
   and  tag='gameid'           
   and htime='session' 
   group by dt, luid
) c1 on a1.dt = c1.dt and a1.creator_uid = c1.luid
group by a1.dt,if(c1.online_duration_huya is null, '单播', '双播')
order by a1.dt