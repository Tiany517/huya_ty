--不同品类用户曝光秀场内容的占比 

select a.mth,igameid,count(a.ukey) as hexin_uv,sum(pv_all) as pv_all,sum(pv_xiuchang) as pv_xiuchang from 
(
        select substr(dt,1,7) as mth,igameid,ukey 
        from zhgametemp.cwq_huya_ukey_shichang_luid_gameid_guishu_mth_v1
        where dt >= '2026-05-01' and dt <= '2026-05-31' --and dt <= '2025-01-23'
        --and igameid in(2336) 
        --and luid in(1354740567) 
        and dt not in('2025-04-26','2025-03-26')
        group by substr(dt,1,7),igameid,ukey 
)a 
left join 
(
select substr(dt,1,7) as mth ,ukey,sum(cnt) as pv_all,sum(if(gameid  in(1663,2165,2633),cnt,0)) as pv_xiuchang from 
  zhgametemp.cwq_huya_app_pageview_click_position_users_v1 
where dt >= '2026-05-01' and dt <= '2026-05-31'
and position in('首页推荐')
and eventid in('pageview/position') 
group by substr(dt,1,7),ukey
)b 
on a.mth = b.mth and a.ukey = b.ukey 
group by a.mth,igameid