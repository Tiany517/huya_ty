# VIP拍脸类型用户日表

目标表：zhgametemp.zty_vip_popup_type_user_d_i_v1，ORC，dt静态分区。
普通字段：popup_type、material_id、uid、exposure_cnt；唯一键dt+material_id+uid。
源口径：show/activity_layer，12个material_id，不限ety，有效登录yyuid；同时过滤同日源dt与stime左闭右开区间。曝光次数为原始上报条数，不额外去重。
同UID可进入多种配置，整体UV不能相加；其他源分区的迟到记录不纳入。

2026-11-13已完成11月1日至12日历史写入，1日任务成功但无记录，2日至12日均有数据。日调度尚未发布。
9日源读取Spark任务两次失败且接口未返回根因，改用Presto提取同口径聚合快照，再以7批Spark静态分区写入：首批overwrite，其余into。写入与源读取引擎分开，未改变业务口径。
9日最终24886行、24881个UID、25685次曝光，与源快照逐键逐值完全一致，重复键与异常行均为0；其余日期汇总与补跑前相同。
完整范围已做目标粒度和异常检查，7日独立源总数已对账；其他日期尚未全部逐键源对账，不把历史全范围标记为全面验收通过。

create.sql为建表；daily-spark.sql为日调度模板，仅覆盖当天分区。backfill-spark.sql为因扫描量被拒绝的历史方案，不再用于提交。
运行记录和剩余校验见backfill-run-20261113.md、validation-record.md。用户级快照与包含UID的恢复SQL只保存在本机，不纳入仓库。
