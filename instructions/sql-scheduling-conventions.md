# 调度版 SQL 编写规范

本文件规定在虎牙数据平台编写、修改和交付调度版 SQL 时必须遵守的结构与检查要求。它与 `AGENTS.md`、`sql-validation-workflow.md` 同时生效。

## 1. 编写前先复用

1. 先检索 `sql/source`，查找相同主题、相同引擎、相同目标表类型和相同分区写法的 SQL。
2. 优先复用仓库中已在调度环境运行过的模板，包括表命名、DDL、注释、分区和重跑方式。
3. 先看模板不代表可以机械复制。每次都要重新核对本次目标表字段、分区字段和最终查询列数。
4. 如果没有可复用模板，再新增通用结构，并在 SQL 头注释中注明复用来源或新增原因。

推荐优先参考：

- `sql/source/AI工坊/AI工坊曝光入口位_按天调度_v2.sql`
- `sql/source/站外主播用户活动明细_指定口径_日跑调度.sql`
- `sql/source/王者荣耀/王者主播潜力_互动过程指标_日跑调度版_Spark.sql`

## 2. 基本结构

调度版 SQL 默认按以下顺序组织：

1. 文件头注释：目的、引擎、时间范围、输入快照、目标表、输出粒度和分区口径。
2. `CREATE TABLE IF NOT EXISTS`：只在目标表不存在时建表，不在脚本中自动删除已有表。
3. 完整 CTE：业务过滤、粒度规整、关联、窗口和最终汇总先定义清楚。
4. `INSERT OVERWRITE TABLE ...`：放在全部 CTE 之后、最终 `SELECT` 之前；只有目标表是分区表时才追加 `PARTITION (...)`。
5. 最终 `SELECT`：只输出目标表需要的字段，不保留调试字段和中间排序。
6. 文件末尾不再追加诊断查询。诊断 SQL 应单独存放或在提交正式 SQL 前临时执行。

分区目标表的通用骨架：

~~~sql
-- 目的、引擎、时间范围、输入快照、目标表、输出粒度和重跑说明

create table if not exists 数据库.目标表 (
    metric_1 string comment '指标1',
    metric_2 bigint comment '指标2'
)
partitioned by (
    dt string comment '统计日期'
)
stored as orc;

with cte_1 as (
    -- 输入粒度、输出粒度、过滤条件和是否允许放大
    select ...
),
cte_2 as (
    select ...
)

insert overwrite table 数据库.目标表
partition (dt = '固定分区值')

select
    metric_1,
    metric_2
from cte_2;
~~~

### 2.1 INSERT 后保持简单查询

调度 SQL 默认采用“建表语句；WITH CTE 完成过滤、JSON 解析、关联和聚合；INSERT OVERWRITE TABLE ... [PARTITION (...)] SELECT 显式字段 FROM 最终CTE;”结构，INSERT 后只接简单字段投影，避免在写入部分嵌套复杂子查询。WITH 与 INSERT 属于同一条语句，中间不得加分号；静态分区字段不重复出现在最终 SELECT。此项是平台调度的优先编写规范，不代表 Spark 不支持 INSERT 后接子查询。源表查询成功不能代替调度写入验证；出现空结果时，必须核对实际发布及宏展开后的 SQL、业务日期、源分区就绪时间、INSERT 执行日志和目标分区，并在同日期、同数据快照、同过滤条件下对比写法。没有日志或对照证据，不得将空结果归因于 CTE/子查询结构或调度平台限制。

## 3. 非分区、静态分区与动态分区

### 3.1 非分区表

调度 SQL 不强制要求 `dt` 或任何分区字段。目标表没有 `PARTITIONED BY` 时，直接覆盖整表：

~~~sql
create table if not exists 数据库.目标表 (
    cohort_mth date,
    tag string,
    metric double
)
stored as orc;

with final_cte as (
    select ...
)

insert overwrite table 数据库.目标表

select
    cohort_mth,
    tag,
    metric
from final_cte;
~~~

规则：

- 非分区表不得写 `PARTITION`。
- 最终 `SELECT` 列数等于目标表全部字段数。
- `INSERT OVERWRITE` 会覆盖整张表，只适用于单任务独立维护的表，或该批次必须整体替换的场景。
- 用户已验证跑通的 `zty_huya_linshi_20260826_left_important_anchor_monitor_qingchun_v1` 就是非分区调度示例。

### 3.2 静态分区

适用场景：一次性分析、月度汇总、固定观察窗口，或目标日期已经由业务分析范围确定。

~~~sql
insert overwrite table 数据库.目标表
partition (dt = '2026-10-31')

select
    metric_1,
    metric_2
from final_cte;
~~~

列数规则：

- 目标表共 18 个普通字段和 1 个分区字段时，静态分区写入只需要返回 18 个普通字段。
- 最终 `SELECT` 不要再返回 dt。
- 如果静态分区有多个字段，分区值必须在 `PARTITION` 子句中全部给定。

### 3.3 动态分区

适用场景：一次查询写入多个分区，或分区值来自查询结果。

很多 Spark/Hive 环境默认使用 `hive.exec.dynamic.partition.mode=strict`。完全动态分区需要在写入前显式设置：

~~~sql
set hive.exec.dynamic.partition.mode=nonstrict;
~~~

~~~sql
insert overwrite table 数据库.目标表
partition (dt)

select
    metric_1,
    metric_2,
    stat_dt as dt
from final_cte;
~~~

列数规则：

- 目标表共 18 个普通字段和 1 个分区字段时，动态分区查询必须返回 19 列。
- 分区字段必须出现在最终 `SELECT` 中，Spark 按位置匹配，通常要求和目标表分区字段顺序一致。
- 分区字段不得为 NULL。上线前必须单独检查动态分区值的覆盖和唯一性。
- strict mode 下只有动态分区、没有静态分区列时，Spark 会在执行阶段报 `Dynamic partition strict mode requires at least one static partition column`。此时要么启用 `nonstrict`，要么改为静态分区。

### 3.4 常见错误

下面两段不能混用：

~~~sql
-- 错误：动态分区，但查询只返回 18 个普通字段
insert overwrite table 数据库.目标表 partition (dt)
select metric_1, metric_2, ... from final_cte;

-- 错误：静态分区，但查询又额外返回 dt，导致插入列数过多
insert overwrite table 数据库.目标表 partition (dt = '2026-10-31')
select metric_1, metric_2, ..., '2026-10-31' as dt from final_cte;
~~~

## 4. 平台参数不等于 SQL 变量

调度平台中的 `taskDate`、实例日期、任务日期等系统参数，不一定已经替换到 SQL 中。

必须区分：

1. 平台日志显示了任务日期，不代表 SQL 中的 `PARTITION (dt)` 自动获得了值。
2. 使用宏变量前，先确认平台实际支持并会进行替换，例如仓库常见写法 `'${tdate?string('yyyy-MM-dd')}'`。
3. 如果平台没有完成变量替换，动态分区查询仍需自己返回分区字段。
4. 不要因为平台有任务日期，就把 `PARTITION (dt)` 当成已经赋值的静态分区。

固定月份分析优先使用静态分区；可复用日跑任务使用仓库已确认的日期宏或目标表动态分区规则。

## 5. 分析窗口与输出分区要分开

分析数据范围和目标表分区是两个不同概念。非分区表没有输出分区，但仍要明确源数据过滤窗口。

例如：

- 源数据时间：2026-10-01 至 2026-10-31。
- 结果分区：`dt='2026-10-31'`。
- SQL 中的事件过滤仍应明确限制在 10 月。
- 不要因为分区是 10-31，就省略源数据过滤，导致全历史扫描。

当源数据分区不完整时，不得静默生成看似正常的月汇总。必须先确认目标日期分区存在。

## 6. 目标表与查询列核对

交付前必须完成以下结构核对：

1. 目标表普通字段清单。
2. 目标表是否分区；如分区，列出版分区字段清单。
3. 非分区表是否完全没有 `PARTITION`；分区表是静态分区还是动态分区。
4. 最终 `SELECT` 字段清单和顺序。
5. 静态分区时：`SELECT` 列数等于普通字段数。
6. 动态分区时：`SELECT` 列数等于普通字段数加分区字段数。
7. 字段名称、顺序和类型与目标表一致；建表注释不能替代类型检查。
8. `round`、`cast`、`coalesce` 等外层表达式可能改变实际类型，必须核对。

建议至少执行一次静态检查，确认 DDL 字段数和主查询字段数，并人工检查第一个、最后一个以及所有分区字段。

## 7. 重跑与幂等性

1. 调度结果表默认使用 `INSERT OVERWRITE`。非分区表重跑会覆盖整表；分区表重跑只应覆盖对应分区，二者都不能累加。
2. 不要使用 `INSERT INTO` 写正式日分区或月分区，除非业务明确要求追加并已有唯一键设计。
3. 重跑必须覆盖同一逻辑分区，不能因执行日期变化写到另一个无业务含义的分区。
4. 目标表已存在时不自动删除或重建；如确需重构表结构，先评估下游兼容性并按高风险操作确认。
5. 如果拆成中间表，必须说明中间表名、分区、覆盖方式和保留周期。

## 8. 性能与扫描范围

1. 事实表先在独立 CTE 中完成分区和业务过滤，再参与大表关联。
2. 避免在全站事实表上直接做多阶段窗口计算，能先缩小用户级或场次级样本时优先缩小。
3. 大表多次扫描时，先核对是否可以通过一次扫描派生多个结果；但不得为了减少扫描而破坏粒度和口径。
4. 大范围时间窗口必须确认扫描数据量、分区数和预估运行时间。
5. Spark 广播 Join 可能因小表实际过大而失败，必要时在调度配置中关闭自动广播。

## 9. 引擎差异

1. Spark SQL：使用当前数据平台 Spark 版本支持的 DDL、CTE、窗口和分区语法。
2. Hive：不得直接假设支持 Spark 的全部函数和 CTE 位置；复用 Hive 模板时按 Hive 语法实现。
3. Presto：主要用于查询分析，不要把 Spark 或 Hive 的建表和分区 DDL 直接用于 Presto 查询任务。
4. 同一业务口径改写引擎时，需保留字段名、粒度、过滤和空值规则，并重新验证。

## 10. 交付前检查清单

1. 是否先检索并复用了仓库现有调度模板。
2. 文件头是否说明目的、引擎、时间范围、快照、目标表、粒度和分区。
3. 是否先建表，再定义 CTE，最后 `INSERT OVERWRITE` 加最终 `SELECT`。
4. 是否确认目标表为非分区表或分区表。
5. 非分区表是否没有 `PARTITION`，且查询列数等于目标表全部字段数。
6. 静态分区是否没有在查询中重复返回分区列。
7. 动态分区是否在查询中返回非空分区列。
7. 是否确认了平台参数是否真的替换进 SQL。
8. 是否使用 `INSERT OVERWRITE` 保证重跑幂等。
9. 是否保留分析窗口与输出分区的区别。
10. 是否没有把诊断字段、小时字段、排序和临时校验查询带入正式脚本。
11. 是否在目标环境实际运行；未运行时状态只能写“待验证”。
12. 是否按 `sql-validation-workflow.md` 完成数据、粒度、指标和交付对账。

## 11. 已知失败案例

2026-11-09 的 VIP 进房弹幕反应调度任务中：

- 目标表包含 18 个普通字段和 1 个分区字段 `dt`，总列数 19。
- SQL 使用了动态分区 `PARTITION (dt)`。
- 最终查询只返回 18 个普通字段。
- Spark 报错：目标表 19 列，插入数据 18 列，且分区列没有常量值。
- 第二次重跑已补 `dt` 查询列，但平台默认 strict mode，仍被完全动态分区限制拒绝：动态分区模式至少需要一个静态分区列，或需要显式设置 `hive.exec.dynamic.partition.mode=nonstrict`。

根因不是 CTE 放在 `INSERT OVERWRITE` 前面。动态分区要求最终查询额外返回分区字段；只有全动态分区时还必须启用 nonstrict，或改用静态分区。最终采用 `PARTITION (dt)`、查询末列 `dt='2026-10-31'` 和 `SET hive.exec.dynamic.partition.mode=nonstrict`。修改仓库文件不等于调度任务已更新，重跑前必须确认 Lighthouse 中实际执行 SQL 已重新发布。

## 12. 相关文档

- `AGENTS.md`
- `AGENTS.en.md`
- `sql-validation-workflow.md`
- `templates/sql-validation-record.md`

英文版见 `sql-scheduling-conventions.en.md`。
