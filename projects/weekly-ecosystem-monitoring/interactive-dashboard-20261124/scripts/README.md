# 刷新脚本

## 快速执行

```bash
python scripts/refresh_dashboard.py \
  --category-csv <category_daily.csv> \
  --anchor-weekly-csv <anchor_weekly.csv> \
  --anchor-daily-csv <anchor_daily.csv> \
  --event-csv <event_user_revenue.csv> \
  --template assets/dashboard_template_multidim.html \
  --output-dir <new_run_dir> \
  --run-name <YYYYWww> \
  --daily-report \
  --platform-daily-csv <platform_daily.csv> \
  --smoke-test
```

无赛事 CSV 时删除 `--event-csv`。已有同名输出时脚本默认拒绝覆盖；明确需要重跑时加 `--overwrite`。启用日报时必须提供官方平台 DAU CSV，不得用品类 DAU 汇总替代全站 DAU。

## 各脚本职责

- `refresh_dashboard.py`：校验输入、推导周列表和最新分区、调用构建/验证/冒烟，并生成运行清单。
- `build_dashboard_data_multidim.py`：CSV 转 dashboard JSON；支持路径、周起点和输出参数化。
- `build_dashboard.py`：将 JSON 注入 HTML 模板。
- `verify_dashboard_package.py`：schema、唯一键、行数、索引、日期、搜索覆盖、数值、赛事状态和开播主播数包含关系验证。
- `smoke_test_dashboard.mjs`：headless Chrome/Edge 加载 HTML，检查标题、Top20、loading 清除和退出码。
- `build_daily_alert_report.py`：从通过校验的 dashboard JSON 生成一页异动日报，计算同星期基线、异常级别、品类/公会/主播层级/主播 Top20、互动率和内嵌自由分析画布数据。
- `test_dashboard_template.mjs`：静态检查主看板的浅色玻璃样式、画布数据属性和交互入口。
- `test_daily_alert_visualization.py`：检查日报画布数据载荷和周期标签口径。
- `test_daily_alert_visualization.mjs`：通过 Chrome 调试端口验证默认平台日趋势、柱状、100% 堆积、内容大类下钻和月粒度。

## 开播主播数字段

- 品类 CSV：`live_anchor_cnt`、`group_live_anchor_cnt`、`total_live_anchor_cnt`。
- 主播周 CSV：`live_days`，取值应为 0–7。
- 主播日 CSV：`is_live`，取值应为 0 或 1。
- 指标口径：当天 `is_live=1` 的 `luid` 去重数，再按当前周期取日均。平台、内容大类和品类使用日级精确去重；公会、层级和主播使用周内开播天数折算。

## 成功输出

```text
<new_run_dir>/
|-- dashboard_data_<run>.json
|-- ecology_dashboard_<run>.html
|-- validation_report_<run>.json
|-- browser_smoke_report_<run>.json
|-- live_anchor_ui_report_<run>.json
|-- accuracy_reconciliation_<run>.md
|-- daily_alert_report_<run>.html
|-- daily_alert_report_<run>.json
|-- daily_alert_report_<run>.md
|-- daily_alert_smoke_report_<run>.json
|-- daily_alert_manifest_<run>.json
`-- run_manifest_<run>.json
```

只有同时满足以下条件才可以发布：

1. 按 skill 的准确性流程从源表独立复算，`accuracy_reconciliation_<run>.md` 结论为 `passed`。
2. `validation_report_<run>.json` 为 `passed`，且 `liveAnchorCountsValid=true`。
3. 开播主播数 UI 专项检查 passed：总盘 KPI、图表、单层表、下钻和主播专项均能显示。
4. `browser_smoke_report_<run>.json` 为 `passed`。
5. `run_manifest_<run>.json` 的路径、行数、字节数和 SHA-256 完整。
6. 启用日报时 `daily_alert_report_<run>.json=passed`，且平台 DAU 来自官方平台活跃用户表。
7. 主看板与日报的自由分析画布回归检查通过，桌面和移动端页面级无横向溢出。

## 单独验证

```bash
python scripts/verify_dashboard_package.py \
  --data <dashboard_data.json> \
  --report <validation_report.json>

node scripts/smoke_test_dashboard.mjs \
  --html <dashboard.html> \
  --report <browser_smoke_report.json>
```

浏览器冒烟找不到 Chrome 时设置 `CHROME_PATH` 或传 `--chrome`。
