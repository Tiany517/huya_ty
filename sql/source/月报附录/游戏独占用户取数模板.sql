select mth,count(distinct ukey) all_num,count(distinct if(game_label='游戏',ukey,null)) youxi_num,count(distinct if(game_label='娱乐',ukey,null)) yule_num from 
(
    select substr(dt,1,7) as mth,game_label,ukey,sum(all_dur) as all_dur from 
    zhgametemp.cwq_huya_ayyuid_session_from_server_with_user_heichan_pachong_v1
    where dt >= '2026-03-01'  and dt <= '2026-04-30' -- 注意每次修改这里，小批量的跑，因为每次数据量都很大
    and heichan_lable = 'not_heichan'
    and pachong_lable = 'not_pachong'
    and user_product in('huya_andriod','huya_ipad','huya_pad','huya_ios') --APP 端
    and game_label in('游戏','娱乐')
    group by substr(dt,1,7),game_label,ukey
)a 
where all_dur > 5
group by mth