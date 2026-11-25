# 赛事诊断接入 / Tournament context

## 中文

2026-11-25：工作台异常等级改为带圆点的柔和标签，居中展示，鼠标悬停提示原异常分；判级不变。研究构建器 `scripts/build_tournament_research.py --evidence-dir <本地证据目录> --dashboard-data <看板JSON>` 独立输出全品类覆盖清单、赛事阈值研究HTML/Markdown和结构核查JSON，不自动替换生产赛事标签。探索SQL位于 `sql/diagnostics/`，验收状态见同目录验收卡；原始结果不随代码提交。

日报生成器支持 `--tournament-context <JSON路径>`，用于接入按日保存的探索证据。JSON包含reportDate、comparisonDate、category、metrics（label/current/previous/scope）、notes、sources；每个指标独立保留来源、粒度和端口径。报告日期必须精确相同，过期样本会报错；未提供时显示待接入，不将缺失映射视为非赛事。

本轮接入的是单品类、两日探索核查，不是正式全品类赛事数据源；原异常分和严重度未变更。生成器的passed仅表示现有构建检查通过，不代表该探索样本通过完整SQL验收。样本数据留在本地，不纳入仓库。

核查顺序：主要下降品类自身开播主播数及开播时长 → 官方北京时间赛程与版权映射 → 当日赛事关联主播DAU及固定名单DAU → 非赛事独占与交叉用户 → 流水、拉新与回流。全站或其他品类供给不能替代本品类供给证据。

版权dt为快照、day为比赛日期；赛事关联压到day/game_id/luid后关联观看，用户按day/game_id/ukey去重。固定名单包含日常直播，不等于纯赛事流量。赛事、非赛事观看存在重叠，不相减不同来源UV。

拉新沿用原表排除mailiang；回流沿用原表，不额外套买量过滤；合计必须求用户并集。当前上游四端不含鸿蒙属于已知范围，页面注明；不计算与含鸿蒙DAU的直接转化率。

比赛日、窗口内休赛日、窗口外、映射未知与流量强度分开。P90只是候选强度线，全品类历史分布和阈值未验证前不得作为正式赛事期筛选器，也不得认定因果影响。

验收：`python -m unittest discover -s scripts -p 'test_*context.py' -v`，并执行日报原测试和`--smoke-test`。检查日期拒绝过期、零基数不显示无穷、HTML转义、缺失不填零；对账HTML/JSON/Markdown。新增模块tournament_context.py必须随构建器一起迁移。

## English

The analyst severity cells now use centered, muted chips with anomaly-score tooltips; classification is unchanged. The standalone research builder accepts an evidence directory and dashboard JSON, reconciles exported aggregates, and emits an exploratory coverage/threshold/cycle report. Diagnostic SQL and its acceptance record live in `sql/diagnostics/`. Raw results remain local; no production labels are automatically published.

Use `--tournament-context <JSON path>` for dated exploratory evidence. Required keys: reportDate, comparisonDate, category, metrics (label/current/previous/scope), notes and sources. The evidence date must match the report exactly. Missing evidence remains pending; absence of a copyright mapping does not prove absence of tournaments.

This integration is a limited diagnostic, not a validated all-category production source. Existing anomaly scores remain unchanged. A build status of passed is not full SQL accuracy acceptance. Compare supply within the affected category; distinguish dynamic tournament-anchor viewing, frozen-cohort viewing and actual match-time audiences. Preserve source-specific client coverage and deduplicate acquisition/return unions. Calendar status and traffic intensity are separate; P90 is an uncalibrated candidate, not an approved tournament-period definition.

Migrate tournament_context.py together with the report builder. Run context tests, existing daily tests and browser smoke checks, then reconcile HTML, JSON and Markdown. Keep evidence and sensitive outputs local.
