select
    dt as "日期"
    ,category as "数据粒度"
    ,game_name as "品类"
    ,luid as "主播UID"
    ,snick as "主播昵称"
    ,is_live as "是否当天开播"
    ,live_mins as "开播时长_小时"
    ,avg_acu as "当天平均ACU"
    ,dau as "DAU"
    ,daily_revenue as "打赏流水"
    ,daily_pay_user_cnt as "打赏人数"
    ,arppu as "人均打赏流水"
    ,avg_view_mins as "人均观时_分钟"
    ,attribution_user_cnt as "归因人数"
    ,interest_user_cnt as "兴趣用户数"
    ,non_category_interest_user_cnt as "非LOL兴趣用户数"
from zhgametemp.zty_category_ecology_health_daily_d_i_0827_v1
where
  dt between '2026-08-31' and '2026-09-06'
  and gameid in (
    1 -- 英雄联盟
    ,2336 --王者荣耀
    ,862 --CS2
    ,2356 --体育
    ,2165 --户外
  )
order by dt, gameid
