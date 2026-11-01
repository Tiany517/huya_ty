retention_monthly as (
  select
    substr(base_dt, 1, 7) as mth,
    pcode,
    game_name,
    sub_category,
    count(distinct base_dt) as cohort_days,
    -- 每个用户日会展开为 D7/D14/D30 三行；只在 retention_day=7 计共同 cohort 基数一次。
    sum(if(retention_day = 7 and is_danmu = 1, 1, 0)) as danmu_base_user_cnt,
    sum(if(retention_day = 7 and is_danmu = 1 and target_is_danmu = 1, 1, 0)) as danmu_7d_retain_user_cnt,
    sum(if(retention_day = 14 and is_danmu = 1 and target_is_danmu = 1, 1, 0)) as danmu_14d_retain_user_cnt,
    sum(if(retention_day = 30 and is_danmu = 1 and target_is_danmu = 1, 1, 0)) as danmu_30d_retain_user_cnt,
    sum(if(retention_day = 7 and is_gift = 1, 1, 0)) as gift_base_user_cnt,
    sum(if(retention_day = 7 and is_gift = 1 and target_is_gift = 1, 1, 0)) as gift_7d_retain_user_cnt,
    sum(if(retention_day = 14 and is_gift = 1 and target_is_gift = 1, 1, 0)) as gift_14d_retain_user_cnt,
    sum(if(retention_day = 30 and is_gift = 1 and target_is_gift = 1, 1, 0)) as gift_30d_retain_user_cnt
  from retention_matched
  group by substr(base_dt, 1, 7), pcode, game_name, sub_category
)
