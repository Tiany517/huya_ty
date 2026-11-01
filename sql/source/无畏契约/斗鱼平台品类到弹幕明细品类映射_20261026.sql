-- 目的：建立斗鱼平台品类（dm_mkt_rowner_day.r_category）到弹幕明细品类
--       （dwt_jingpin_danmulog_day.r_category）的映射，避免因品类命名不一致
--       导致弹幕用户留存分母被错误算成 0。
-- 时间口径：基于 2026-03 的同主播同日品类共现结果确定首版别名和父类归并。
-- 输出表：zhgametemp.douyu_dm_to_dwt_category_map_20261026

create table zhgametemp.douyu_dm_to_dwt_category_map_20261026 as
with same_name_map as (
    select distinct
        p.r_category as dm_category,
        p.r_category as dwt_category,
        '同名直接匹配' as mapping_type,
        '高' as mapping_confidence,
        '已确认' as mapping_status,
        1 as enabled,
        '候选主播品类表与弹幕明细品类同名' as evidence
    from zhgametemp.douyu_multi_category_candidate_pairs_20261026 p
),
explicit_map as (
    select 'Apex英雄' as dm_category, 'APEX' as dwt_category,
           '英文别名' as mapping_type, '高' as mapping_confidence,
           '已确认' as mapping_status, 1 as enabled,
           '2026-03同主播日共现84次，占95.45%' as evidence
    union all
    select 'QQ飞车手游', 'QQ飞车', '端手游命名差异', '高', '已确认', 1,
           '2026-03共现31次，占100%'
    union all
    select 'DOTA1', 'DOTA', '历史名称差异', '中', '已确认', 1,
           '2026-03共现4次，占11.76%；DOTA1仍保留同名映射'
    union all
    select 'lol云顶之弈', '云顶之弈', '平台端前缀差异', '高', '已确认', 1,
           '2026-03共现85次，占21.74%'
    union all
    select '主机', '主机游戏', '父类归并', '高', '已确认', 1,
           '2026-03共现255次，占29.96%'
    union all
    select '主机', '主机其他游戏', '父类归并', '高', '已确认', 1,
           '2026-03共现475次，占55.82%'
    union all
    select '刀塔自走棋', '自走棋', '游戏别名', '高', '已确认', 1,
           '2026-03共现144次，占93.51%'
    union all
    select '守望先锋归来', '守望先锋', '版本后缀差异', '高', '已确认', 1,
           '2026-03共现50次，占100%'
    union all
    select '星秀+颜值', '颜值', '父类归并', '高', '已确认', 1,
           '2026-03共现39次，占66.10%'
    union all
    select '星秀+颜值', '才艺', '父类归并', '高', '已确认', 1,
           '2026-03共现18次，占30.51%'
    union all
    select '星秀+颜值', '星秀', '父类归并', '中', '已确认', 1,
           '2026-03共现2次，占3.39%'
    union all
    select '暴雪', '炉石传说', '暴雪游戏归并', '高', '已确认', 1,
           '2026-03共现431次，占49.71%'
    union all
    select '暴雪', '魔兽世界', '暴雪游戏归并', '高', '已确认', 1,
           '2026-03共现233次，占26.87%'
    union all
    select '暴雪', '魔兽争霸', '暴雪游戏归并', '高', '已确认', 1,
           '2026-03共现88次，占10.15%'
    union all
    select '暴雪', '星际争霸', '暴雪游戏归并', '高', '已确认', 1,
           '2026-03共现40次，占4.61%'
    union all
    select '暴雪', '守望先锋', '暴雪游戏归并', '高', '已确认', 1,
           '2026-03共现10次，占1.15%'
    union all
    select '暴雪', '魔兽怀旧服', '暴雪游戏归并', '中', '已确认', 1,
           '暴雪父类下的已知魔兽分支'
    union all
    select '暴雪', '暗黑破坏神', '暴雪游戏归并', '中', '已确认', 1,
           '暴雪父类下的已知暗黑分支'
    union all
    select '传奇聚合', '传奇', '聚合页归类', '高', '已确认', 1,
           '2026-03共现13次，占100%'
    union all
    select '火影忍者手游', '火影忍者', '版本后缀差异', '高', '已确认', 1,
           '2026-03共现31次，占91.18%'
    union all
    select '雀魂麻将', '雀魂', '名称缩写', '高', '已确认', 1,
           '2026-03共现59次，占100%'
    union all
    select '魔兽争霸3', '魔兽争霸', '版本后缀差异', '高', '已确认', 1,
           '2026-03共现88次，占100%'
    union all
    select '绝地求生', '天天吃鸡', '绝地求生替代分类', '中', '已确认', 1,
           '2026-03共现326次，占25.83%；弹幕表无同名绝地求生分类'
    union all
    select '绝地求生', '热门游戏', '游戏泛分类', '需复核', '待确认', 0,
           '2026-03共现507次，占40.17%；可能是PUBG内容，但泛分类存在污染风险'
    union all
    select '太空鹅鸭杀', '鹅鸭杀手游', '名称差异', '需复核', '待确认', 0,
           '弹幕表存在鹅鸭杀手游分类，但候选主播样本暂无稳定共现证据'
)
select *
from (
    select * from same_name_map
    union all
    select * from explicit_map
) t;

-- 校验：映射表覆盖全部候选平台品类，且每个平台品类至少有一条启用映射。
select
    count(*) as mapping_rows,
    count(distinct dm_category) as dm_categories,
    count(distinct case when enabled = 1 then dm_category end) as enabled_dm_categories,
    count(distinct case when mapping_status = '待确认' then dm_category end) as pending_dm_categories
from zhgametemp.douyu_dm_to_dwt_category_map_20261026;
