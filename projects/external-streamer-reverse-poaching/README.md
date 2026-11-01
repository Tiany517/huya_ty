# 外部平台主播反挖估算项目复盘

本项目复盘历史“反挖”脚本如何把斗鱼、B站、抖音和快手的主播行为特征，映射为虎牙侧 ACU、拉新、收入和月薪的启发式估计。它保留可继续迭代的模型函数、匿名统计和方法限制。

“反挖”在这里表示外部主播发现、筛选和潜力估算，不表示已经接触、签约或完成迁移。预测值也没有与对应主播在虎牙的实际结果逐人匹配，因此不能当作已验证的招聘效果。

## GitHub 路径地图

| GitHub 路径 | 内容 |
| --- | --- |
| `projects/external-streamer-reverse-poaching/README.md` / `README.en.md` | 中文 / 英文项目背景、关键结果和迁移边界 |
| `projects/external-streamer-reverse-poaching/methodology/model-and-validation.md` / `.en.md` | 输入字段、公式、参数、版本漂移、已知缺陷和复用步骤 |
| `projects/external-streamer-reverse-poaching/scripts/fanwa_estimator.py` | 去除 HDFS 凭据和上传副作用后的斗鱼/B站/抖音/快手估算函数 |
| `projects/external-streamer-reverse-poaching/scripts/summarize_fanwa_anonymized.py` | 从本地原始结果生成匿名平台、品类和内部基准汇总 |
| `projects/external-streamer-reverse-poaching/scripts/audit_model_reproducibility.py` | 对比源文本与最终 CSV，并检查当前脚本能复现哪些历史预测 |
| `projects/external-streamer-reverse-poaching/scripts/validate_fanwa_project.py` | 仓库级完整性、匿名化和基础一致性校验 |
| `projects/external-streamer-reverse-poaching/artifacts/anonymous-summary/` | 中英文匿名平台汇总、品类汇总、虎牙主播市场月度基准和模型复现报告 |
| `projects/external-streamer-reverse-poaching/artifacts/validation-report.json` | 最近一次自动校验结果 |
| `projects/external-streamer-reverse-poaching/source-manifest.csv` | 源文件大小、SHA-256、处理方式和排除原因 |

仓库：<https://github.com/Tiany517/huya_ty>。以上是仓库内路径；目录可拼到 GitHub 的 `tree/main/`，文件可拼到 `blob/main/`。

## 项目背景与数据链路

历史流程分两套：

1. 斗鱼 / B站：从 `cys_huya_jingpin_fanwa_feat2` 读取六个月特征，输出基础特征和四个预测字段，再写入按日期命名的临时表。
2. 抖音 / 快手：从 `cys_huya_jingpin_doukuai_fanwa_6mon_uidcate` 读取在线人数分位、粉丝、开播时长等特征，单独输出 ACU、拉新和月薪预测。

源脚本把 `HADOOP_USER_NAME` 和自动 `drop table`、下载、上传命令直接写在代码中。仓库版本只保留纯计算函数和本地文件接口，不连接集群，也不执行任何远端写操作。新电脑重跑前应从加密保险包恢复身份，并重新核验当前表名、分区和权限。

## 已归档结果概览

`06allres.csv` 是本次唯一保存下来的最终预测表，仅覆盖斗鱼和 B站：

| 平台 | 记录数 | 唯一主播ID数 | 预测ACU为0比例 | 预测ACU P50 | 预测ACU P90 | 预测拉新 P50 | 预测月薪 P50 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| B站 | 29,975 | 23,095 | 36.340% | 50 | 150 | 50 | 1,650 |
| 斗鱼 | 4,334 | 2,920 | 17.328% | 50 | 500 | 50 | 1,650 |
| 合计 | 34,309 | 26,015 | - | - | - | - | - |

单位说明：

- `predict_acu`、`predict_laxin` 是模型估计的人数指标，不是平台官方值。
- `predict_pay` 按每月 20 个开播日、每日 5.5 小时和品类分段费率估算，口径上视为“月薪代理值”。
- `predict_yingshou` 的周期和金额单位没有在原脚本中定义，只能当作收入特征，不能直接宣称月收入。
- `liucun`、`avg_com`、`danmu`、`fans`、`dingyue_add`、`danmu_only`、`danmu_new`、`live_mins`、`gift_user`、`gift_value` 是外部平台的输入特征；单位必须以源表字段字典为准。

匿名品类汇总只保留每个平台至少 20 条记录的品类，共 289 个“平台 × 品类”行。另有 438 个自然日、2024-06-01 至 2025-08-12 的虎牙内部主播 ACU 市场基准；源字段名称是 `主播acu` 和 `主播num`，原始字段定义没有文档，本仓库只把它当作时间趋势和量级参照。

## 必须保留的解释边界

1. 这是硬编码参数的启发式映射，不是回归、机器学习训练模型，也没有时间外验证或样本外误差指标。
2. 预测值由人工选定参考主播、品类权重、上限和平台缩放系数产生；这些参数会显著改变排序，不能把预测值写成事实。
3. 当前归档脚本没有包含抖音、快手的最终输出表，因此本仓库不能给出这两类平台的匿名成果汇总。
4. 历史结果与当前脚本存在版本漂移。当前脚本能逐行复现全部 34,309 行 `predict_acu`，也能复现全部斗鱼 `predict_laxin`；B站 `predict_laxin` 仅复现 23,262 / 29,975 行（77.605%）。如需追溯旧排名，必须以历史 `06allres.csv` 为准，不能拿当前参数倒推成“原始方法”。
5. 斗鱼/B站的 `danmu_new` 分支使用 `danmu_only` 作为上限来源，疑似实现缺陷；为保持历史可追溯性，仓库版原样保留并标注，不擅自修改。
6. 抖音脚本中 `predict_acu` 和 `predict_laxin` 调用同一个函数，两者必然相同；没有证据表明这是经业务验证的合理设计。
7. 原脚本包含 HDFS 身份和远端写表命令，已从仓库版本删除。源归档中如有凭据，应视为已暴露并轮换。

完整公式、参数和版本差异见 `methodology/model-and-validation.md`。

## 校验

在仓库根目录运行：

```powershell
python projects/external-streamer-reverse-poaching/scripts/validate_fanwa_project.py
```

如本机仍有原始目录，可额外执行：

```powershell
$env:FANWA_SOURCE_DIR='<本机反挖源目录>'
python projects/external-streamer-reverse-poaching/scripts/validate_fanwa_project.py --write-report
```

校验覆盖记录数、平台分布、唯一主播键、匿名 CSV 表头、脚本硬编码凭据、虎牙基准月份数，以及源文件之间的基础字段一致性。`model-reproducibility.csv` 单独记录当前脚本对不同历史预测字段的复现率。

## 迁移边界

本仓库未复制约 503 MB 的源目录，也未复制两个培训视频、RAR、原始 `06allres.csv`、`res.txt`、`featt`、含主播名称和 UID 的逐行结果、checkpoint、缓存或 `mailall.tar.gz` 中的原始 Hive 数据和邮件配置。

`报警邮件` 子目录实际是独立的虎牙经营告警自动化项目，不属于本模型；它同时包含 HDFS 身份、邮件发送逻辑和大量原始数据，因此没有混入本项目。若后续需要迁移，应单独做脱敏和告警口径复盘。

## 新电脑复用步骤

1. 先读本文件和 `methodology/model-and-validation.md`，不要把预测值当成实测结果。
2. 在加密保险包中恢复数据平台身份，但不要把它写回脚本。
3. 重新确认输入表的最新分区、字段单位、空值编码和权限。
4. 使用 `fanwa_estimator.py` 做本地计算，再与历史 `06allres.csv` 或新目标表逐人、逐平台对账。
5. 若要更新业务决策，先定义标签、阈值和人工复核机制；没有真实虎牙后续结果时，只能称为“候选发现”，不能称为“反挖成效”。

英文版见 `README.en.md`。
