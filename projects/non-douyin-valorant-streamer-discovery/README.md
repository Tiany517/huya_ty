# 非抖无畏主播挖掘复盘

## 项目目的

在 B 站、斗鱼和快手识别 2026 年曾进入无畏契约头部层、且持续跑赢平台增长基准的潜在主播。项目服务于无畏契约站外主播挖掘和引入判断，不等同于主播实际可挖性、合作意愿或引入收益预测。

## 来源与本机映射

原始目录：`C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\非抖无畏主播挖掘`。

| 资产 | 本机来源 | GitHub 归档 |
| --- | --- | --- |
| 主数据工作簿 | `非抖无畏主播挖掘.xlsx` | 不上传；含主播 ID 与昵称 |
| 最终版工作簿 | `非抖无畏主播_头部基准筛选_含战队与剔战队_20261014.xlsx` | 不上传；仅保留匿名聚合 |
| 剔除战队工作簿 | `非抖无畏主播_剔除战队_平台基准筛选_20261014.xlsx` | 不上传；仅保留匿名聚合 |
| 最终筛选脚本 | `scripts/build_final.py` | [`scripts/build_final.py`](scripts/build_final.py) |
| 回归验证脚本 | `scripts/verify_final2.py` | [`scripts/verify_final2.py`](scripts/verify_final2.py) |
| 剔除战队计算 | `scripts/build_select_team.py` | [`scripts/build_select_team.py`](scripts/build_select_team.py) |
| 剔除战队工作簿生成 | `scripts/build_team_xlsx.py` | [`scripts/build_team_xlsx.py`](scripts/build_team_xlsx.py) |
| 匿名平台与筛选汇总 | 本次重新聚合 | [`artifacts/non-douyin-discovery-summary.csv`](artifacts/non-douyin-discovery-summary.csv) |
| 匿名月度基准 | 最终版“平台月度基准”页 | [`artifacts/non-douyin-monthly-benchmarks.csv`](artifacts/non-douyin-monthly-benchmarks.csv) |
| 匿名附件重建脚本 | 本次复盘 | [`scripts/prepare_anonymized_artifacts.mjs`](scripts/prepare_anonymized_artifacts.mjs) |

主数据工作簿为 2,154 行、519 个唯一主播，月份覆盖 2026-01 至 2026-09；SHA256 为 `ea8137016c5967ea0233d620190e73d61b4e52495164aa4f6ae2bd76da9a6b27`。工作簿含主播名、主播 UID 和逐主播月度表现，未进入 GitHub。

## 样本与口径

- 平台：`bilibili`、`douyu`、`kuaishou`；唯一主播数分别为 378、54、87。
- 层级：头部 `有效acu >= 2000`；颈部 `1000-1999`；腰部 `100-999`；尾部 `<100`。
- 候选池：2026 任一月份曾达到有效 ACU 2,000。
- 环比：`(本月有效 ACU - 上月有效 ACU) / 上月有效 ACU`，仅计算相邻自然月且上月 ACU 大于 0 的记录。
- 战队主播：主播名曾以 `EDG/BLG/DRG/JDG/XLG/TYL/FPX/TEC/TE/WOL/AG/NOVA` 开头；采用“任意月份曾带前缀”的严格口径。
- 基准：战队主播使用平台头部中位并含战队；B 站非战队使用平台头部中位并剔除战队；斗鱼和快手因头部样本只有 0 至 2 个，改用平台全体中位。
- 入选：跑赢基准的月份占比不低于 50%；可比月数至少 4 为“稳健”，至少 2 为“仅放宽”；且 2026-09 必须仍有数据。
- 月度序列以主播为观察对象，使用来源工作簿的月度 `有效acu`；环比只在同一主播相邻两个自然月均有正 ACU 时计算，不是用户日或月度去重用户口径。

## 已核结果

2026-09 共有 249 个主播有数据、270 个无数据。有数据主播中，头部 17、颈部 22、腰部 88、尾部 122。旧版分层工作簿只保留了 248 个真实行，漏掉 1 个 B 站头部件，并把头部写成 16；本复盘以主数据工作簿为准。

最终候选共 34 人，其中 B 站 29、斗鱼 3、快手 2；可评估 29 人。最终入选 11 人，全部来自 B 站；其中稳健 10 人、仅放宽 1 人，战队 7 人、非战队 4 人。

未入选的 23 人原因分别为：最近无 2026-09 数据 11 人、未跑赢一半月份 10 人、可比月数不足 2 人。斗鱼和快手的候选最后均无 2026-09 数据，因此不能把“0 人入选”解释为这两个平台没有潜力主播。

剔除 24 个战队主播后，候选从 34 降至 26，可评估从 29 降至 21，相邻月对数 103。按头部中位基准入选 6 人，按平台整体中位基准入选 15 人；后者只用于敏感性参考。

完整匿名数字见 [`artifacts/non-douyin-discovery-summary.csv`](artifacts/non-douyin-discovery-summary.csv)，逐平台逐月基准见 [`artifacts/non-douyin-monthly-benchmarks.csv`](artifacts/non-douyin-monthly-benchmarks.csv)。

## 已知限制与运行注意

1. `有效acu` 在本项目中直接作为平台官方或抓取侧指标使用；仓库没有字段字典，新电脑复跑前应确认单位和统计窗口。
2. B 站头部样本相对充足；斗鱼和快手头部样本过少，最终筛选混用平台整体中位，三个平台的入选规则并不完全同构。
3. “最近无 9 月数据”无法区分停播、漏采、跨平台改名和平台接口缺失，不能直接解释为退出直播。
4. 主播名战队前缀是业务近似识别，不是合同或公会归属表；改名和未带前缀的战队主播可能漏判。
5. 归档脚本默认使用记录的本机源目录，并支持环境变量 `NON_DOUYIN_VALORANT_DIR`；新电脑必须把该变量指向主数据工作簿实际所在目录。
6. `build_select_team.py` 会生成 `_state_team.pkl`；该中间态没有归档。必须先在相同源目录运行它，再运行 `build_team_xlsx.py`。
7. 早期 v3 的文档文字曾写“可评估 28 人”，但候选表实际为 29 人；最终版及本次独立聚合均确认 29 人。
8. 匿名附件重建脚本依赖 `@oai/artifact-tool`。原始工作簿不随仓库分发，因此没有源文件时只能阅读已生成的匿名 CSV。

英文版见 [`README.en.md`](README.en.md)。
