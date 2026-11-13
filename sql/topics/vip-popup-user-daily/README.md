# VIP拍脸类型用户日表

2026-11-13已通过BigData MCP的Spark建表成功，rid=1241323692366679040，状态SUCCESSED；另以get_table_ddl独立读回结构，确认4个普通字段、dt分区、ORC。
表：zhgametemp.zty_vip_popup_type_user_d_i_v1。
字段：popup_type（配置定向类型）、material_id（配置ID）、uid（有效登录yyuid）、exposure_cnt（原始曝光上报次数）、dt（stime自然日）。
逻辑唯一键dt+material_id+uid；同UID可进入多个配置或类型，整体人数须重新去重。
只创建了表，未写入曝光数据、未回补历史、未发布或启用平台调度。
create.sql为实际执行建表；daily-spark.sql为配套日写入草稿，使用仓库tdate宏，只覆盖目标当天分区。
过滤沿用讨论结果：show/activity_layer、12个material_id、不限ety、有效UID；按同日源dt与stime过滤。不含其他源分区迟到事件。
已通过源样本确认14559和14491在material_id，其他ID仍需数据核验；配置可能修改投放时间，不据当前截图硬编码全部历史窗口。
源日期覆盖、异常、独立逐用户对账及真实写入验收未执行；日调度稿不可标为已验证。
