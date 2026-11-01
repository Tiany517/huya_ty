# 历史报告文件

保留的 DOCX 已扫描文本和 OOXML，没有发现 `mobile/<hash>` 形式的用户标识。报告中的图表是生成结果，原始用户级数据和聚类标签工作表不在仓库中。

| 仓库内路径 | 对应历史版本 | 使用状态 |
| --- | --- | --- |
| `device-profile-harmony-vs-android-v2.docx` | 鸿蒙 vs 安卓 V2 | 优先查看该设备报告。它聚焦两组，不复现三组聚类页 |
| `device-profile-three-groups-legacy.docx` | 鸿蒙、安卓、苹果三组旧版 | 只作历史对照。12 个聚类占比都错写为 100.0%，不能用；匿名汇总已给出正确组内占比 |
| `snooker-world-championship-tgi.docx` | 斯诺克世锦赛用户画像 TGI | TGI 描述部分可对照 CSV；报告内总记录数、音乐 App 占比和聚类结果存在冲突，不能整份标记为已验证 |
| `world-championship-viewers-10min.docx` | 世锦赛 10 分钟以上观看用户 | 可对照 10 分钟以上观看队列，但它是观看人群，不是“拉新用户”；聚类基于 50,000 人样本，轮廓系数较弱 |

报告是可读的业务交付物，不是底层数据。继续使用前先查 `../validation/validation-report.md`。

英文版见 `README.en.md`。
