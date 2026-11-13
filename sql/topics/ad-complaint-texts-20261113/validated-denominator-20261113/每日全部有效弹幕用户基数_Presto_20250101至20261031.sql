-- Presto SQL；2026-11-13已运行并通过独立对账。rid=1241323839112793088。
-- 业务目标：补齐“每日抱怨广告用户数 / 每日全部有效发弹幕用户数”的分母。
-- 样本、日期、UID过滤、passed和内容优先级完全沿用用户原SQL。
-- 输入：弹幕记录，无已确认消息唯一键；中间：dt+uid唯一；输出：dt唯一。
-- 不排除主播本人，不删除完全相同的源记录，不额外过滤端或品类。
-- 无join、union或窗口展开；重复发送只计一名用户，条数保留重复。
-- 可按月修改下面的dt范围分批执行，合并后dt不得重复。

with danmu_base as (
    -- 输入/输出均为源弹幕记录，过滤不放大。
    select
        substr(d.dt, 1, 10) as dt,
        cast(d.luid as varchar) as uid,
        coalesce(
            nullif(trim(d.askscontent), ''),
            nullif(trim(d.scontent), '')
        ) as content
    from gamelive.gamelive_huya_danmu_log d
    where d.dt between '2025-01-01' and '2026-10-31'
      and d.passed = '0'
      and d.lpid is not null
      and coalesce(lower(trim(cast(d.luid as varchar))), '')
          not in ('0', '', 'null', 'other', '-', '-1')
),

user_day as (
    -- 源弹幕记录 -> dt+uid唯一。总分母只要求非空文字，不要求含“广告”。
    select
        dt,
        uid,
        count(*) as user_danmu_cnt,
        max(case when content like '%广告%' then 1 else 0 end) as mention_ad,
        sum(case when content like '%广告%' then 1 else 0 end) as user_mention_ad_cnt
    from danmu_base
    where content is not null
    group by dt, uid
)

select
    dt,
    count(*) as danmu_user_cnt,
    sum(user_danmu_cnt) as danmu_cnt,
    sum(mention_ad) as mention_ad_user_cnt,
    sum(user_mention_ad_cnt) as mention_ad_cnt
from user_day
group by dt
order by dt

-- 导出字段：
-- dt：源分区日期；danmu_user_cnt：每日全体有效文字弹幕用户数（最终分母）；
-- danmu_cnt：全体有效文字弹幕记录条数（仅辅助对账）；
-- mention_ad_user_cnt / mention_ad_cnt：含广告用户数/条数，须与本地明细逐日精确对账。
-- 预期：2025-01-01到2026-10-31应有669个日期。缺日期需查分区，不能直接补零。
-- 后续只需按dt把danmu_user_cnt填入Excel每日结果的黄色列；原SQL用户口径不变。
