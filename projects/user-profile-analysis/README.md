# 用户画像、TGI 与聚类分析复盘

本项目整理 2026 年的设备用户画像、斯诺克/世锦赛观看用户画像、TGI 对比、KMeans 聚类和底层取数 SQL。迁移目标是让新电脑上的 Codex 能区分“可复算的描述性结果”“历史报告中的口径错误”和“无法从现有文件重建的模型结果”。

项目没有上传用户级明细。原始 CSV 中的 `user_ukey`、`mobile/<hash>`、设备标签、逐用户画像和聚类标签均未进入 Git；仓库只保留匿名汇总、源文件哈希、报告文件、SQL 原文和校验证据。

## GitHub 路径地图

| 仓库内路径 | 内容 |
| --- | --- |
| `projects/user-profile-analysis/README.md` / `.en.md` | 中文 / 英文项目背景、结论、限制和复用步骤 |
| `projects/user-profile-analysis/methodology/profile-tgi-and-clustering.md` / `.en.md` | 样本、时间窗、TGI 公式、KMeans 设置、SQL 逻辑和报告版本差异 |
| `projects/user-profile-analysis/sql/` | 3 份源 SQL 原文，未擅自修复；已知错误在静态审查表中定位 |
| `projects/user-profile-analysis/reports/` | 4 份历史 DOCX；文件职责、替代关系和已知表述问题见 `reports/README.md` |
| `projects/user-profile-analysis/artifacts/anonymous-summary/tgi/` | 设备三组、斯诺克拉新、世锦赛观看和 10 分钟以上观看的中英文 TGI 汇总 CSV |
| `projects/user-profile-analysis/artifacts/anonymous-summary/clusters/` | 设备三组与 10 分钟以上观看用户的匿名聚类汇总、KMeans 曲线、设备价格分层，以及一套不可勾稽的斯诺克聚类样本汇总 |
| `projects/user-profile-analysis/artifacts/anonymous-summary/sql-static-audit.csv` / `.en.csv` | 8 项 SQL 静态审查：7 项已确认缺陷、1 项字段语义未执行 |
| `projects/user-profile-analysis/artifacts/anonymous-summary/source-manifest.csv` / `.en.csv` | 151 个源文件的路径、大小、SHA-256 和纳入/排除原因 |
| `projects/user-profile-analysis/artifacts/anonymous-summary/project-summary.json` | 队列人数、样本量、附件行数和隐私边界 |
| `projects/user-profile-analysis/artifacts/validation-report.json` | 49 项机读校验结果 |
| `projects/user-profile-analysis/validation/validation-report.md` / `.en.md` | 八类闸门、独立复算、已知问题和未执行项 |

以上均为 GitHub 仓库根目录下的相对路径。

## 四个队列

| 分析 | 目标组 | 对照组 | 可复核状态 |
| --- | ---: | ---: | --- |
| 设备画像：鸿蒙、安卓、苹果 | 172,312 / 390,718 / 145,179 | 两两比较 | TGI 汇总的计数、占比闭合和公式可复算；原始 CSV 无法复现三组全量 |
| 斯诺克拉新画像 V2 | 1,072 | 2,676 | TGI 表可复算；报告聚类无法由保留样本重建 |
| 世锦赛观看用户 | 208,206 | 366,543 | TGI 表可复算；报告叙事存在版本冲突 |
| 世锦赛观看 10 分钟以上 | 192,764 | 395,788 | TGI 表、聚类样本与价格分层可对账；不能称为“拉新用户” |

所有 TGI 表的每个维度都回到固定组分母，目标组和对照组占比在该维度内闭合到 100%，保留一位小数的 TGI 最大复算误差为 `0.05`。这只证明汇总算术一致，不证明字段口径、抽样代表性和业务结论正确。

## 主要可复用结果

设备三组中，鸿蒙用户的财富评分均值 `2.14`，高于安卓 `1.68` 和苹果 `0.91`；鸿蒙有房率 `73.62%`、安卓 `25.44%`。鸿蒙相较安卓的 App 二级分类“直播”占比为 `47.09%` 对 `24.61%`，TGI `191.3`。这些数值可在 `tgi/device-harmony-vs-android.csv` 中逐项定位。

世锦赛观看 10 分钟以上的用户中，46 岁以上占比 `9.01%`，对照组 `2.94%`，TGI `306.5`；华为设备 TGI `119.1`；有车率 `40.10%`，对照组 `34.09%`，TGI `117.6`。完整 255 行结果见 `tgi/world-championship-viewers-10min.csv`。

设备三组各自抽取 50,000 用户做 KMeans，原报告把每个聚类都写成 `100.0%`，属于明确的分母或格式错误。匿名汇总重新计算后，例如鸿蒙四类占比为 `27.56% / 35.32% / 27.10% / 10.03%`，安卓为 `42.16% / 16.82% / 12.16% / 28.86%`，苹果为 `26.86% / 49.23% / 19.36% / 4.54%`。

10 分钟以上观看用户的 KMeans 为 K=4、轮廓系数 `0.1434`，属于弱结构，只适合描述该次样本的分群差异，不应把聚类昵称当成稳定的人群定义。样本四类人数为 `22,609 / 15,870 / 6,076 / 5,445`，合计 50,000。

## 关键数据质量结论

1. `各设备用户画像数据.csv` 有 178,432 行、178,244 个唯一用户标识和 188 条重复标识行；设备系统只有 iOS 178,412 行和 Android 20 行，无法回算报告宣称的 708,209 人三组总体。该文件是敏感明细，未迁移。
2. `processed_data_v2.csv` 有 1,086 行、1,074 个唯一标识和 12 条重复标识行；报告的斯诺克聚类是 1,072 人，聚类标签也不一致。该文件含伪匿名标识，未迁移，只保留明确标注为“不可勾稽”的聚合。
3. 设备 SQL 的过滤条件写 `huya_andriod`，CASE 写 `huya_android`。按存储版本无法可靠得到 Android 队列，现存 CSV 不能仅凭这份 SQL 复现。
4. 世锦赛观看 SQL 的目标窗口为 2026-04-18 至 05-06，对照组为 04-18 至 05-04，两组少两天观察机会；注释还把 2026 写成 2025。
5. “单日观看时长最长”SQL 实际对全期间 `watch_duration` 求和，并引用未定义的 `ot_watch_longest_duration_user`；两个输出分支还共用同一标签。
6. 旧设备报告 12 个聚类全部显示 `100.0%`；斯诺克总报告写 3,767 条记录，但 TGI 分母合计 3,748；音乐 App 占比同时出现 `56.2%` 和 `63.1%`；10 分钟画像报告把 192,764 名观看用户误写成拉新用户。

详细证据见 `validation/validation-report.md` 和 `artifacts/anonymous-summary/sql-static-audit.csv`。

## 迁移边界

- 保留 3 份 SQL 原文、4 份最终或历史报告、7 份中英文 TGI 汇总、聚类与价格分层匿名汇总、源文件清单和校验脚本。
- 不保留用户级 CSV、含 `user_ukey` 的 XLSX 工作表、132 张重复生成图、Python 缓存和大型中间产物。
- 不把旧报告中的错误聚类占比、错误“拉新”措辞或不可复现的 KMeans 标签继续当作已验证事实。

## 新电脑复用步骤

1. 先读 `methodology/profile-tgi-and-clustering.md` 和 `validation/validation-report.md`，确认每个队列的分母与时间窗。
2. 用 `tgi/` 中的 CSV 继续描述性分析；遇到极小分母时，同时看人数、占比和置信度，不要只按 TGI 排序。
3. 重新跑 SQL 前先修复产品枚举、画像快照归属、比较窗口、CTE、单日指标和分组标签，并按通用 SQL 验收卡记录证据。
4. 重新做 KMeans 时固定采样键、随机种子、特征、缺失处理和标准化方式；不能用报告中的聚类昵称反推字段映射。
5. 当前 `watch_duration` 的单位、窗口和黑产过滤仍标为“未执行”，必须在取得字段字典后用独立查询确认。

英文版见 `README.en.md`。
