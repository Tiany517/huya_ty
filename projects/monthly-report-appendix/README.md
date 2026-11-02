# 月报附录：外部生态与 APP 游戏独占

## 项目目的

保留 2026 年月报附录中可复用的 SQL、匿名时间序列、口径说明和已知问题，使新电脑上的 Codex 能继续更新以下工作：

1. 视频号 MCN 单播、双播主播的每日和每月 DAU。
2. 抖音、视频号、其他端外平台的月度直播 DAU。
3. 抖音 MCN 按游戏品类拆分的直播 DAU。
4. 虎牙 APP 次月留存和游戏/娱乐用户独占占比。

## GitHub 路径地图

| GitHub 路径 | 内容 |
| --- | --- |
| `projects/monthly-report-appendix/README.md` / `README.en.md` | 中文 / 英文项目说明、口径、风险和刷新步骤 |
| `projects/monthly-report-appendix/scripts/export_anonymous_artifacts.py` | 从已复核源文件重抽匿名结果并执行一致性校验 |
| `projects/monthly-report-appendix/artifacts/external-ecosystem-dau-monthly-2026.csv` | 2026 年抖音、视频号、其他平台和合计月 DAU |
| `projects/monthly-report-appendix/artifacts/video-channel-stream-type-monthly.csv` | 2025-09 至 2026-10 视频号单播和双播老内容月 DAU |
| `projects/monthly-report-appendix/artifacts/douyin-mcn-category-dau-monthly-2026.csv` | 2026 年抖音 MCN 按游戏品类拆分的月 DAU |
| `projects/monthly-report-appendix/artifacts/video-channel-mcn-daily-2026-05-25_2026-08-18.csv` | 视频号 MCN 单播/双播日 DAU 和有效 DAU |
| `projects/monthly-report-appendix/artifacts/app-next-month-retention-monthly.csv` | 2021-01 至 2026-02 APP 次月留存率 |
| `projects/monthly-report-appendix/artifacts/app-game-exclusive-monthly.csv` | 2022-01 至 2026-08 APP 游戏独占、娱乐独占和重合用户 |
| `projects/monthly-report-appendix/artifacts/source-manifest.csv` | 已复核源文件的大小和 SHA-256 |
| `projects/monthly-report-appendix/artifacts/validation-summary.json` | 行数、覆盖范围、复算结果和已知缺口 |
| `sql/source/月报附录/视频号月报_单播_双播_DAU取数.sql` | 视频号 MCN 单播/双播日表的原始 SQL |
| `sql/source/月报附录/视频号DAU_分单播和双播_主播下钻.sql` | 视频号单双播月度主播下钻 SQL |
| `sql/source/月报附录/视频号单双播主播下钻_final.sql` | 另一版主播下钻 SQL；存在日期范围和月均值风险，使用前必须修正 |
| `sql/source/月报附录/游戏独占用户取数模板.sql` | APP 游戏/娱乐独占用户取数模板 |

## 核心结果

### 端外平台月 DAU

`external-ecosystem-dau-monthly-2026.csv` 覆盖 2026-01 至 2026-10。2026-10 只统计到 10 月 20 日，不能与完整月份直接比较。各月 `抖音 + 视频号 + 其他 = 合计`，源图表内部对账差异为 0。

### 视频号单播和双播

`video-channel-stream-type-monthly.csv` 覆盖 2025-09 至 2026-10。`双播老内容` 是源图表字段名，不能改写成所有双播内容。单播与双播老内容相加等于源图表合计，内部对账差异为 0。

`video-channel-mcn-daily-2026-05-25_2026-08-18.csv` 共 170 行、85 个有数据日期，每个有数据日期恰有单播和双播两行。源 CSV 缺少 2026-08-01，附件没有把缺失日补为 0。2026-06、2026-07 的日表月均值按整数展示后与图表月值一致；2026-08 因缺一天不能直接用日表月均值替代图表值。

### 抖音 MCN 品类 DAU

`douyin-mcn-category-dau-monthly-2026.csv` 保留游戏品类级 DAU，不包含 MCN 排名、主播名或主播 UID。2026-04 至 2026-08，各品类加总与图表总计存在最大 `377,465.451613` 的差额；源图表没有给出能解释该差额的额外品类，因此保留原值并标记为未闭合，不能强行调平。

### APP 次月留存和游戏独占

`app-next-month-retention-monthly.csv` 覆盖 2021-01 至 2026-02，共 62 个月。该序列从月报附录 PPT 图表恢复，复核目录中没有对应底层 SQL，因此只能复现图表值，不能证明当前取数方法可重跑。

`app-game-exclusive-monthly.csv` 覆盖 2022-01 至 2026-08，共 56 个月。字段包括总用户、游戏独占、娱乐独占、重合用户和三类占比。游戏独占用户由“游戏用户数 - 重合用户数”复算，娱乐独占用户由“娱乐用户数 - 重合用户数”复算；三类占比逐月加总为 100%，最大浮点误差为 `1.11e-16`。

## SQL 审查结论

### `视频号月报_单播_双播_DAU取数.sql`

- 当前日期范围为 2026-05-25 至 2026-06-14。
- 同日与虎牙开播时长表匹配到有效时长时标记为双播，否则标记为单播。
- `有效DAU = DAU × 0.26`，0.26 是源表采用的换算系数，不是视频号直接提供的有效 DAU。
- `count(distinct userid)` 是源 SQL 的主播数口径；后续必须确认 `userid` 在视频号表中的业务含义与唯一性。

### `视频号DAU_分单播和双播_主播下钻.sql`

- 日期范围为 2026-06-01 至 2026-08-18。
- 月 DAU 用“月内 DAU 合计 / 该月实际观察天数”，有效 DAU 继续乘 0.26。
- 结果包含主播 UID 和昵称，因此只归档 SQL，不归档源结果明细。

### `视频号单双播主播下钻_final.sql`

- `huya_anchor_day` 的下界写成 `2015-06-01`，与注释中的 2025 年范围不一致。
- `anchor_2025_game_duration` 注释写 2025 年，实际过滤到 2026-12-31。
- 最终查询直接 `sum(a.dau)`，没有像前一份 SQL 一样除以观察天数，不能直接当作月日均 DAU。
- 文件虽名为 `final`，状态只能标为“草稿/待验证”。正式复用前必须修正时间范围和月日均公式，并重新执行数据、粒度、关联和导出对账。

### `游戏独占用户取数模板.sql`

- 当前日期范围为 2026-03-01 至 2026-04-30，以后刷新必须更新起止日期和最新分区。
- 仅纳入非黑产、非爬虫用户，APP 端限定 Android、iPad、Pad 和 iOS。
- 游戏、娱乐分别先按月聚合用户观看时长，再要求 `all_dur > 5`。
- 游戏独占与娱乐独占是“该类用户数减重合用户数”，不是直接用 `youxi_num / all_num`。

## 隐私边界

以下源文件未上传：

- `202601-外部生态数据整理_模板.xlsx` 和 `202608外部生态数据整理.xlsx`，因为包含主播 UID、昵称、合同、收入和其他商业化明细。
- 全部 PPT 原稿，因为含 MCN、公会、主播身份或未脱敏商业数据。
- 主播下钻结果和任何用户级明细。

仓库只保留匿名平台、品类、月度或日度聚合值与源哈希。

## 刷新步骤

1. 先确认最新数据分区和报告截止日。
2. 更新 SQL 日期后，先逐条执行数据可用性、唯一键、关联放大和指标不变量检查。
3. 运行 `scripts/export_anonymous_artifacts.py` 重抽附件；2026-08-01 仍缺失时继续明确披露，不得补零。
4. 抖音 MCN 品类总和与总计不一致时，先追查缺失品类或统计口径，不得为了凑平修改原图。
5. 月报引用部分月份时，必须在标题或脚注写明“截止 YYYY-MM-DD”。

English version: `README.en.md`.
