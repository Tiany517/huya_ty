--日度主播明细
select a1.dt, a1.userid, f1.usernickname, nick, if(c1.online_duration_huya is null, '单播', '双播') as luid_type, first_dt, online_duration, online_duration_huya, dau, liushui, anchor_reward_income, shouru
from (
  select dt,userid,creator_uid,sum(cast(audiencecnt as bigint)) as dau,sum(cast(onlinetimeduration as double)) as online_duration,sum(cast(liveroomrewardcnt as double)) as liushui
,sum(cast(anchorrewardincome as double)) as anchor_reward_income,sum(cast(findertotalincome as double)) as shouru
  from gamelive.dwd_spider_wxmcn_anchor_livedata_list_d_i a 
  left join (
    select pid as creator_uid    ---主播uid
            ,vx_vedio_id           ---微信视频号
    from  gamelive.ods_live_huya_vedio_stream_push_conf_1760614652931321858
    where dt = date_add(cast(current_date as varchar), -1) --取最新日期
    group by pid,vx_vedio_id 
  ) b on a.userid = b.vx_vedio_id
  where dt>='2026-07-01' and dt <= '2026-07-20'
  and cast(onlinetimeduration as double) > 0 -- 开播
  -- and userid in ('sph8KVv3uxE1LY3','sphosEfxN4Ut5TO','sphReL8M8ZYdxCW','sphsmqJXgBTQvOc')
  group by dt,userid,creator_uid
) a1 
left join (
  select uid as luid,nick,roomid,first_live_time
  from gamelive.dim_huya_ayyuid_info
  where dt = date_add(cast(current_date as varchar), -1)
)b1 on a1.creator_uid = b1.luid
left join (
   select dt, luid, sum(cast(online_duration as double)/1000/3600) as online_duration_huya
   from gamelive.dwt_huya_ayyuid_session_from_server_no_user          
   where dt>='2026-07-01' and dt <= '2026-07-20'
   and length(dt)=10          
   and  tag='gameid'           
   and htime='session' 
   group by dt, luid
) c1 on a1.dt = c1.dt and a1.creator_uid = c1.luid
left join (
  select userid, min(dt) as first_dt
  from gamelive.dwd_spider_wxmcn_anchor_livedata_list_d_i
  where dt <= date_add(cast(current_date as varchar), -1)
  and cast(onlinetimeduration as double) > 0 -- 开播
  group by userid
) d1 on a1.userid = d1.userid
left join (
  select userid, usernickname
  from (
    select userid, usernickname, row_number()over(partition by userid order by dt desc) as rk 
    from gamelive.dwd_spider_wxmcn_anchor_livedata_list_d_i
    where dt >= date_add(cast(current_date as varchar), -365)
    and dt <= date_add(cast(current_date as varchar), -1)
    and length(usernickname) > 0
  ) t 
  where rk = 1
) f1 on a1.userid = f1.userid