# Bigdata MCP 迁移说明

本目录归档虎牙公司数据平台 `bigdata` MCP 的可迁移客户端配置、工具契约、调用规范、故障排查和新电脑恢复步骤。目标是让新电脑上的 Codex 能重新连接同一类授权服务，同时不把账号、passport、API secret、查询结果或用户数据写入 Git。

## GitHub 路径地图

| GitHub 路径 | 内容 |
| --- | --- |
| `mcp/bigdata/README.md` / `README.en.md` | 中文 / 英文恢复和使用说明 |
| `mcp/bigdata/config.example.toml` | Codex MCP 客户端配置模板；只含网关地址和审批策略，不含凭据 |
| `mcp/bigdata/tool-catalog.json` | 当前客户端可识别的 11 个工具、参数和安全边界 |
| `mcp/bigdata/smoke-test.sql` | 新电脑连接后的最小 Presto 连通性检查 |
| `vault/migration-secrets.aesgcm` | 加密后的数据平台账号/API 凭据；仓库不保存明文 |

## 迁移边界

已归档：

1. Codex 连接 `bigdata` 所需的 `mcp_servers.bigdata` 配置形态。
2. 当前工具清单、用途、关键参数和默认安全策略。
3. Presto/Spark 选择、单语句执行、查询轮询、结果下载和分区检查规范。
4. 常见认证、网关和查询错误。
5. 凭据的加密保存与恢复位置。

没有归档：

1. 虎牙内部 MCP 服务端源码或二进制。当前客户端配置连接的是由公司维护的远程网关，本机没有可独立打包的服务端实现。
2. `app_id`、`passport`、`X-BIGDATA-SECRET`、Cookie、请求签名或任何实际凭据值。
3. MCP 查询返回的用户级明细、签名下载链接和大结果文件。

因此，GitHub 中的内容可以让新 Codex 理解并重新配置该 MCP，但远程工具本身仍需公司网络权限和有效凭据。

## 新电脑配置

1. 先安装并登录新电脑上的 Codex。确认能够访问公司内网或所需 VPN。
2. 打开 `config.example.toml`，把其中的 `[mcp_servers.bigdata]` 和 `[mcp_servers.bigdata.tools.*]` 合并到新电脑的 `%USERPROFILE%\.codex\config.toml`。不要用模板整体覆盖已有配置，否则会丢失其他 MCP。
3. 重启 Codex，确认工具列表中存在 `mcp__bigdata__execute_sql`、`mcp__bigdata__get_latest_partitions` 和 `mcp__bigdata__get_table_ddl`。
4. 从仓库外安全转移 `huya_ty-env-files.key`，解密 `vault/migration-secrets.aesgcm`，读取 `credentials/bigdata-platform.txt`。
5. 把 `app_id` / `passport` 写入 Codex、组织凭据存储或网关要求的 Header。不要把值写进本仓库、SQL、聊天、shell 历史或配置文件模板。
6. 执行 `smoke-test.sql` 的 `SELECT 1` 检查；通过后再运行只读的 `SHOW TABLES` 或 `get_table_ddl`。
7. 正式取数前重新核对权限、环境和最新分区，再按项目需要下载结果。

## 环境与引擎

- 默认环境：`domestic`。仅在公司海外面向场景下使用 `overseas`。
- 默认引擎：Presto。Presto 因语法、内存或能力限制失败后，再改写为 Spark；不要因为单次超时就静默切换并混用结果。
- 一次 `execute_sql` 只提交一条语句。多条校验语句必须拆开执行；尤其不要把 `create table`、`insert overwrite` 和 `select` 串在同一次调用中。
- `wait_for_result` 和 `timeout` 只控制客户端等待和轮询，不改变实际任务。长任务应记录 `rid`，再用 `get_query_status` 检查。
- 大结果优先用 `get_query_result`，默认上限 500 MB。只有在已经评估内存、磁盘和业务用途后才使用 `download_query_result_raw`。
- 需要本地文件时，优先使用带短期签名和认证 Header 的下载方式；不要把签名 URL 或认证 Header 写入 SQL 或 Git。

## 工具调用契约

| 工具 | 用途 | 关键边界 |
| --- | --- | --- |
| `execute_sql` | 执行 Presto/Spark SQL | 默认 `wait_for_result=true`；长查询先拿 `rid`，不要重复提交同一任务 |
| `get_query_status` | 按 `rid` 看进度、状态和错误 | 这不是结果下载；结果尚未就绪时继续轮询 |
| `get_query_result` | 安全下载结果，默认 500 MB 上限 | 大多数下载优先使用此工具 |
| `download_query_result_raw` | 无大小检查的原始下载 | 只用于已确认结果规模和用户授权；可能造成内存/超时问题 |
| `get_download_url` | 生成带认证 Header 的短期下载 URL | 不记录 URL、`X-BIGDATA-APP` 或 `X-BIGDATA-SECRET` |
| `get_latest_partitions` | 查看表最新分区 | 取“某天以后”数据前必须调用或等价核验 |
| `get_table_ddl` | 查看建表语句和 catalog 全名 | 查询时使用返回的 `full_name`，不要自行猜测 catalog |
| `get_table_metadata` | 查看字段元数据 | 只作为语义证据；字段单位仍需业务和数据抽样确认 |
| `query_data_lineage` | 查上游/下游 Lighthouse 数据血缘 | 只做关系证据，不替代字段口径确认 |
| `get_task_detail` | 查看 Lighthouse 任务及读写依赖 | 不修改生产任务 |
| `query_event_data` | 查 Doris 事件埋点定义 | 先确认 product/event 口径；结果不是用户行为明细本身 |

完整参数定义见 `tool-catalog.json`。

## 标准取数流程

1. 确认业务问题、目标表、时间范围、粒度、唯一键、分子和分母。
2. 用 `get_table_ddl` / `get_table_metadata` 核对字段和 catalog 全名。
3. 用 `get_latest_partitions` 确认真实覆盖，不能把“没有分区”当成“用户未留存”。
4. 用 Presto 执行最小只读探查；必要时改写 Spark。
5. 保存 `rid`、引擎、环境、实际运行范围、耗时、结果行数和输出路径。
6. 先输出小样本/聚合对账，再下载完整结果；涉及用户级明细时再次确认本地用途和清理规则。
7. 报告、SQL、阶段表、目标表、CSV/XLSX 逐项对账；未执行项目明确标为“未执行”。

## 常见错误

| 现象 | 含义 | 处理 |
| --- | --- | --- |
| `Missing credentials` | 客户端没有收到认证 Header 或运行参数 | 检查安全凭据注入，不要猜密码 |
| `status=1003` / Header 验证失败 | `app_id` 与 `passport` 缺失、错位或失效 | 核对凭据映射并重新认证，不要把值发到聊天 |
| `status=1006` | 网络、网关或传输失败 | 检查 VPN/内网和网关状态，不等于分区为空 |
| `SHOW PARTITIONS` 不被 Presto 支持 | 引擎语法差异 | 改用支持的查询或 `get_latest_partitions` |
| 查询成功但结果未就绪 | 异步任务仍在执行 | 保留 `rid`，用 `get_query_status` 继续检查 |
| 下载超过 500 MB | 默认安全阈值被触发 | 聚合、裁剪字段或明确授权后用受控方式下载 |

## 安全检查

- MCP 配置中只允许出现网关地址和审批策略；`app_id`、`passport`、secret、Cookie 和签名 URL 不得出现。
- 不把 MCP 返回的认证 Header 当作普通数据传递。
- 每次写入或覆盖前确认目标表、分区、影响范围和回滚方式。
- 查询用户级数据后，优先保留匿名汇总；明细仅按用户明确要求保存，并记录删除/保留周期。
- 如果网关地址本身被组织视为敏感，可把仓库中该行替换为内部密钥管理引用；当前私有仓库按用户明确要求保留连接模板。

英文版见 `README.en.md`。
