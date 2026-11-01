# 虎牙星秀留存分母修复说明

## 问题

原脚本 `zty_huya_xingxiu_subcategory_monthly_retention_dau_v1.sql` 在 `retention_candidate` 中把每个用户日展开成 D7、D14、D30 三行。后续 `retention_monthly` 直接对 `sum(is_danmu)` 和 `sum(is_gift)` 求共同 cohort 基数，使分母变成正确值的三倍；留存用户数仅在对应 horizon 参与计数，因此没有同步放大。结果是弹幕和打赏各 horizon 留存率都约为正确值的 1/3。

## 已验证证据

- 数据平台读取该目标表成功，当前有 132 行聚合结果，最新月份为 2026-10；2026-10 的留存基数均为 0，因为脚本把留存 base 截止在 2026-09-30。
- 全部 132 行中，122 行的弹幕基数能被 3 整除，126 行的打赏基数能被 3 整除；其余行基数为 0 或不满足条件。
- 2026-09 星秀整体：弹幕基数为 1,655,709，推断正确基数为 551,903；D7 留存用户 171,629，现存率 10.37%，按未重复分母应约为 31.10%。打赏基数为 812,301，推断正确基数 270,767；D7 留存用户 53,574，现存率 6.60%，应约为 19.79%。
- 2025-01 至 2026-10 的 22 个“星秀-整体”月份中，所有非零弹幕和打赏分母都能被 3 整除；因此按原表基数除以 3 推断正确分母没有取整误差。
- 按修正后的“星秀”映射检查 2025-01-01 至 2026-10-29：弹幕和打赏源均覆盖 667 个自然日，缺口均为 0；本轮 D7/D14/D30 目标日期不存在分区缺口。
- 匿名全期对比见 [`../artifacts/huya-xingxiu-overall-retention-comparison.csv`](../artifacts/huya-xingxiu-overall-retention-comparison.csv) 和英文版 [`../artifacts/huya-xingxiu-overall-retention-comparison.en.csv`](../artifacts/huya-xingxiu-overall-retention-comparison.en.csv)。

## 修复方式

用 [`corrected-retention-monthly.sql`](corrected-retention-monthly.sql) 中完整的 `retention_monthly` CTE 替换原脚本同名 CTE。关键变化是基数只在 `retention_day = 7` 时计一次：

```sql
sum(if(retention_day = 7 and is_danmu = 1, 1, 0)) as danmu_base_user_cnt
sum(if(retention_day = 7 and is_gift = 1, 1, 0)) as gift_base_user_cnt
```

修复后重新生成目标表，再运行 [`verify-huya-retention-output.sql`](verify-huya-retention-output.sql)。验证查询会：

1. 检查月度基数相对旧结果是否不再约为三分之一。
2. 输出修正后留存率。
3. 检查留存分子不大于基数。
4. 汇总弹幕与打赏各自目标分区的日期覆盖和缺口。

## 未解决风险

- 原脚本仍以左连接目标日；目标分区缺失会把用户计为未留存。重跑前必须确认 D7/D14/D30 所需日期都有源分区。
- 星秀 DAU 只统计 App 端并剔除黑产/爬虫；用户活动留存来自直播弹幕与礼物事件，两套用户范围不完全相同，不能把留存基数直接当作 DAU 成分。
- 2026-10 留存为空是 cohort 截止规则的结果，不应解释为零流失。
- 子类可以按主播日多标签拆分；同一用户可进入多个子类，“星秀-整体”与子类结果不能简单相加。

英文版见 [`README.en.md`](README.en.md)。
