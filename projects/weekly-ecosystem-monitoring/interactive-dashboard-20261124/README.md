# 虎牙生态监控看板资料包

版本日期：2026-11-24

本资料包用于迁移互动看板的取数、构建、验证和刷新工作流。GitHub 仓库不提交运行版 HTML 或内嵌 JSON；新电脑按 SQL 重新取数后，在本机生成单文件 HTML。

## 先看什么

1. `docs/看板全流程与表格口径_2026-11-24.md`：需求演进、数据流、每张表的口径、公式、覆盖范围和已知限制。
2. `docs/表格口径与SQL资源_2026-11-24_新增开播主播数.xlsx`：适合业务和数据同学快速查阅的口径卡，已包含开播主播数。
3. `sql/README.md`：当前生产、待回刷和历史参考 SQL 的区别。
4. `scripts/README.md`：跨电脑刷新命令、验证命令和失败处理。
5. `skill/huya-ecology-dashboard-refresh/SKILL.md`：可直接安装到 Codex 的自动刷新工作流。

启用自动日报时，刷新命令增加 `--daily-report --platform-daily-csv <platform_daily.csv>`。日报使用官方平台活跃用户表计算 DAU，并生成品类、公会、主播层级和主播 Top20 异动归因；品类 DAU 不用于冒充全站 DAU。

## 当前成品

- 运行版看板：不进入 GitHub，由 `refresh_dashboard.py` 在当前电脑生成；目录边界见 `dashboard/README.md`
- 新增指标：开播主播数，按当天 `is_live=1` 的 `luid` 去重后计算周期日均
- 源表：`zhgametemp.zty_category_ecology_health_daily_d_i_0827_v1`
- 品类/平台日数据：2026-01-01 至 2026-11-23
- 主播/公会/层级周数据：2026-10-12 至 2026-11-22（W42–W47）
- 赛事支付属性：尚未产出，`eventStatus=pending`，赛事筛选不可用于 DAU、归属用户和互动对比

## 快速刷新

在一台已安装 Python、Node.js 和 Chrome/Edge 的电脑上：

```bash
python scripts/refresh_dashboard.py \
  --category-csv <category_daily.csv> \
  --anchor-weekly-csv <anchor_weekly.csv> \
  --anchor-daily-csv <anchor_daily.csv> \
  --event-csv <event_user_revenue.csv> \
  --template assets/dashboard_template_multidim.html \
  --output-dir <new_run_dir> \
  --run-name <YYYYWww> \
  --smoke-test
```

没有赛事 CSV 时删除 `--event-csv`。发布前还必须按 `skill/huya-ecology-dashboard-refresh/SKILL.md` 完成源表独立准确性复算，并生成 `accuracy_reconciliation_<run>.md`；只有准确性复算、`validation_report_<run>.json=passed`、开播主播数 UI 专项检查和浏览器冒烟通过且运行清单完整，才能发布 HTML。

新电脑需要由 Codex 自动识别工作流时，把 `skill/huya-ecology-dashboard-refresh` 复制到该电脑的 `%USERPROFILE%\.codex\skills\`，重新打开 Codex 后可直接调用该 skill。

## 目录

```text
生态监控看板_资料包_2026-11-24/
|-- README.md
|-- 文件清单_SHA256_2026-11-24.csv
|-- docs/
|   |-- 看板全流程与表格口径_2026-11-24.md
|   `-- 表格口径与SQL资源_2026-11-24_新增开播主播数.xlsx
|-- dashboard/
|   `-- README.md（不提交运行版 HTML 和 JSON 的边界说明）
|-- examples/
|   `-- W47_active_anchor_v2/（新增开播主播数后的验证、冒烟与运行清单样例）
|-- assets/
|   `-- dashboard_template_multidim.html
|-- sql/
|   |-- README.md
|   |-- core/
|   `-- reference/
|-- scripts/
|   |-- README.md
|   |-- refresh_dashboard.py
|   |-- build_dashboard_data_multidim.py
|   |-- build_dashboard.py
|   |-- verify_dashboard_package.py
|   `-- smoke_test_dashboard.mjs
`-- skill/
    `-- huya-ecology-dashboard-refresh/
```

## 发布边界

原始 CSV、主播 UID、RoomID 和用户级明细不应上传到公开仓库。覆盖正式看板前要得到用户明确授权，并保留上一版可恢复副本。

`文件清单_SHA256_2026-11-24.csv` 记录资料包内各文件的相对路径、字节数、SHA-256 和状态；跨电脑传输后应重新计算并核对。

`examples/W47_active_anchor_v2` 保留了新增“开播主播数”后的真实验证样例：源表独立复算 passed、数据验证 passed、开播主播数 UI 专项检查 passed、headless Chrome 冒烟 passed，并记录了输入/输出哈希。
