---
name: huya-ecology-dashboard-refresh
description: 刷新、迁移或验收虎牙生态监控 HTML 看板与异动日报时使用；包含从 BigData 取数、CSV 交接、独立准确性复算、JSON/HTML 重建、自由分析画布、自动核验、浏览器验收到发布回滚的完整可执行流程。
---

# 虎牙生态监控看板刷新

## 指标驱动与赛事之外异动（2026-11-25）

刷新日报时同步迁移 `scripts/analyst_upgrade.py` 与 `assets/analyst_upgrade.js/.css`，构建时用 `--metric-supplement` 指向补充查询结果目录。完整口径与验收卡见 `references/METRIC_UPGRADE.md`，不得把核心构建的passed当作补充指标准确性通过。

执行闭环：先查分区/端/字段；复用补充SQL并保存原始返回；检查日品类唯一键与拉新+回流−交集=并集；核对互动join匹配率和分子大于分母记录；再构建独立指标榜单与日期画布；运行Python单测和 `node scripts/test_metric_upgrade.mjs 成品HTML路径`；完成独立源表复算、基础单位抽查和浏览器视觉验收后才能正式发布。任何高风险核查未执行须在页面及验收卡中标待验证。

赛事可复用模板位于 `sql/templates/赛事品类日并集阈值.sql`，通过 `scripts/render_tournament_template.py` 传入明确起止/快照日期生成新SQL。版权记录须先标准化中文game_id，再按dt/gameid/luid去重；观看事实先过滤再关联，最终按dt/gameid/ukey求并集。独立复算必须另用EXISTS半连接抽查至少5个基础日并逐项对账，不能复用被验CTE。P90是候选，不是最终大赛事标签：须结合单赛事周期、官方排期与观看占比复核。体育等无版权覆盖不等于非赛事。

通过标准：键无重复；缺失日期不静默补零；并集恒等式逐行成立；每个层级/指标的绝对贡献占比合计100%（非零变化）；独立复算关键UV精确一致、金额误差不超过0.01元；分母语义一致、窗口完整。互动率若分子/分母语义不通过，只展示有明示限制的互动人数探索趋势，不能生成正式互动率贡献与级别。新增拉新/回流/互动阈值为试运行，必须标注未回测。剔除登记赛日对照不能写成已排除赛后效应或因果归因。

## 异动分析工作台（2026-11-25）

日报新增工作台使用 `scripts/daily_analysis.py`，构建器与该模块必须一起迁移。按全品类日表的 DAU、流水、付费人数、归属用户数、开播主播数分别重算排名，不能先取 DAU Top50 再排序。所有指标须有报告日及前4个同星期记录；缺记录不得补零。连续异常须逐日满足原异常级别且方向相同，缺记录中断，最多28天；上限标记为≥28。累计偏离是逐日相对基线的变化之和，人数指标不能视为去重流失人数。

流水拆解用本期流水/人数和各自基线中位数构造ARPPU，以对称两因素方法分摊变化。两个效应之和必须在0.01元误差内回到流水变化；付费人数任一侧为零时显示不可拆解。这是描述性拆解，不能认定因果。公会、主播保留完整周榜，不能将其伪装成日级持续异常。

发布前运行 `python -m unittest discover -s scripts -p 'test_daily*.py' -v`；运行原日报浏览器回归后再运行 `node scripts/test_daily_analysis.mjs`，核对5指标、全品类候选、流水排名、拆解闭合与连续天数上限。此模块、两个新增测试和构建器需同步到桌面和全局Skill。


## 日报V1.2工作流与硬门槛

V1.2独立构建，不自动覆盖旧日报。迁移时复制 `scripts/build_daily_v12.py`、其现有依赖 `analyst_upgrade.py/build_daily_alert_report.py/daily_analysis.py/tournament_context.py` 及这些文件的现有依赖，和 `assets/daily_v12.html/.css/.js`、`daily_v12_engine.mjs`、`anomaly_filters.mjs`。依赖缺失停止，不手工拼半截HTML。

日报摘要必须采用分析师笔记结构，而不是指标通报：先给“分析师判断”，再分别写“洞察（对判断的进一步解释）、现象（结果指标与品类证据）、原因（过程指标和暂时不能排除/确认的解释）、建议（具体排查对象与下一步）”。洞察不得重复顶部判断；所有判断区分事实、推断和待验证项。页面采用渐进披露：日期口径集中在页首，赛事剔除明细、长诊断解释、下一层明细和口径说明可折叠，原始全期证据与品类/公会/主播主表保持默认展开；“展开全部/收起全部”和折叠状态需持久化。

摘要正文固定为 3–5 张从宏观到微观递进的洞察卡，当前生产版为“平台→品类→公会→主播→抵消与背离”5 层。每张卡都必须独立保留“洞察→现象→原因→建议”四段，不能只在下钻归因表里给贡献值，也不能用一段指标通报替代分析师解释。公会和主播卡必须落到具体对象，至少包含主播昵称、UID、公会、品类、本期与比较期的非赛事日均、非赛事有效日、开播天数及互动人数变化；正向抵消卡用同一口径给出可复制的正向样本。长口径说明默认折叠，不能遮挡首屏结论。

1. 复用前述核心CSV/JSON及独立复算流程，确认实际分区、端范围、唯一键和日期。补充数据未返回不补零，失败查询保留但不作为输入。
2. 赛事剔除视图先执行 `sql/templates/赛事品类前10赛事日.sql`：按品类赛事关联 DAU 降序、日期升序打破并列，取 `ceil(赛事关联正向日数 × 10%)`。导出列必须为 `dt,gameid,event_dau,event_day_count,rn`，校验 `dt × gameid` 唯一，并独立抽查至少5个品类行数与 event_dau。未覆盖版权记录的品类标“赛事覆盖未知”，不得当非赛事。
3. 用 `python scripts/build_daily_v12.py --data <不可变JSON> --platform <含鸿蒙官方平台CSV> --supplement <补充查询目录> --event-top <赛事前10%CSV> --output <新目录>` 构建。新电脑自行取数；原始数据和内嵌HTML不要求进GitHub。
4. 先运行 `node scripts/test_anomaly_filters.mjs`、`node scripts/test_daily_v12_engine.mjs`；设置 `V12_TEST_RUNTIME` 为装有jsdom的外部测试目录，再运行 `node scripts/test_daily_v12_ui.mjs <HTML>`。DOM测试不等于浏览器视觉通过。
5. 用 `python scripts/reconcile_daily_v12.py --data <原始JSON> --html <HTML> --output <对账JSON>` 独立读取原始列，逐行核对6项品类指标及周日原记录；再运行 `node scripts/reconcile_daily_v12_engine.mjs <HTML> <对账JSON>`，核对独立 Python 周聚合以及主播/公会微观事件剔除结果与 JS 引擎。当前基线应至少通过56项周聚合和30项微观路径对账；新增周期须重新计算预期数量，不得只沿用计数。关键UV必须精确一致、金额误差≤0.01元。此步不能代替源表独立查询。

主播与公会的赛事剔除使用“主播周主路径”：主播日表本身不含品类和公会，因此每个主播每期先取该周DAU最大的“品类+公会”作为主路径，再按该路径品类的大赛事日分别从本期和比较期剔除；两期各至少保留3个非赛事有效日才可进入微观测算。公会值等于可归因主播主路径非赛事日均之和，主播与品类之间允许重叠；赛事映射未覆盖的品类不得进入微观归因，更不能写成“无赛事”。两期非赛事有效星期结构不同时，平台层差值只用于方向校验，不解释为赛事净效应。
6. 平台拉新回流必须按用户日并集；独立查询用不同集合路径复算每日期的拉新/回流/并集/交集，保存SQL和查询rid。仅有5日不得冒充连续历史。补充独立验证SQL见项目 `sql/diagnostics/13_平台拉新回流独立集合复算_20261124.sql`，执行新周期时先按实际快照改日期。
7. 实际浏览器核对首屏、tooltip、日期、下钻返回、8主播比较、模块拖拽/恢复、宽窄屏。V1.2 首屏必须同时显示“原始全期（未剔赛事）”与“非赛事 vs 非赛事”，所有 KPI 和摘要标题写明本期与比较期；DAU 过程指标不得默认用付费指标解释，流水过程必须包含互动/付费/ARPPU。未执行写未执行。保留19项验收矩阵、输入和产物哈希、测试记录、回测候选报告；正式替换前备份。

准确性门槛：缺失不补零；比率分子分母共同有效行且同端/用户语义；百分率差异用百分点、ARPPU等用原单位；多日流水拆解用观看用户日总量而非DAU日均，Shapley闭合误差≤0.01元；搜索、TopN、等级过滤不改变完整父级贡献分母；层级固定参考周名单，新增退出与升降层分开并明示固定周期。公会周最大开播天数不等于主播日并集，未复算不作正式供给评级。

互动率语义失败时封锁正式比率及评级；四端拉新回流不含鸿蒙明确备注。赛事剔除当前指“各品类赛事关联 DAU 前10%日期”，不是官方赛事窗口；缺官方周期核验不声称已排除赛后效应。未覆盖赛事记录的品类显示待判断，不得推断为非赛事。公会、主播层级和主播只有周聚合时，不生成日级赛事剔除评级。试行混合评级没有低分支，不能把正常改低；保留带方向分，优先级独立。异常分候选必须历史回测、案例核验且用户确认后才切换，不将报警率称准确率。

English: Build V1.2 into a new directory. Independent export-to-UI and warehouse reconciliation are separate gates. DOM success is not browser acceptance. Preserve pending metrics and trial ratings; never silently fill missing data or publish score-only grades.

## 目标与完成定义

把新周期数据安全地更新进单文件 HTML 看板，并留下能够复核的源数据、SQL、口径、验证结果和运行记录。本文件是可执行主流程；references 只用于查字段、公式和补充清单，不能在主流程未执行时替代验收。

一次刷新只有同时满足以下条件，才能称为“完成”：

1. 三个核心 CSV 已按契约生成并完成跨电脑哈希核对。
2. 原始源表已完成独立准确性复算，不是只用构建脚本检查自己生成的 JSON。
3. `validation_report_<run>.json` 的 `status` 为 `passed`，所有 `checks` 均为 `true`。
4. 使用 `--smoke-test` 时，`browser_smoke_report_<run>.json` 的 `status` 为 `passed`。
5. `run_manifest_<run>.json` 已记录实际日期范围、输入/输出路径、字节数、SHA-256 和命令。
6. 已人工抽查首屏、时间切换、自由维度下钻、自由分析画布、Top20 和主播搜索结果。
7. 正式覆盖交付物前已取得用户明确许可，并保留上一版可恢复副本。
8. 启用日报时，`daily_alert_report_<run>.json` 的 `status` 为 `passed`，日报冒烟通过，且平台 DAU 来自官方平台活跃用户表。

如果缺少源表复算、浏览器冒烟或人工抽查，只能报告“结构校验通过”或“数据校验通过”，不能报告“全流程通过”。

## 开始前门禁

执行任何 SQL 或写文件前，先确认并记下：

1. 当前期、对比期的起止日期，以及选择日/周/月/季/年时的完整时间桶。
2. 源表实际最新可用分区。用户要求的结束日期晚于最新分区时，以实际分区为准并明确写出止期。
3. 主播周表覆盖的所有 `week_start` 是否为周一、是否连续、日表是否落在该区间内。
4. 当前数据是否包含公会；空公会是否按“无公会”展示。
5. 赛事支付属性是否已回刷。没有赛事 CSV 时保持 `pending`，赛事筛选不能用于 DAU、归属用户或互动对比。
6. 输出目录、运行名和是否需要覆盖已有成品。覆盖正式成品必须得到用户明确许可。
7. 本机是否具备 Python、Node.js、Chrome/Edge。没有浏览器环境时不得声称浏览器冒烟通过。

不要把账号、API 密钥或其他凭据写入 SQL 注释、CSV、JSON、运行清单或交付文档。

## 输入输出契约

另一台电脑或另一位数据同学只交付 CSV，不交付手工修改过的 JSON 或半截 HTML。

| 文件 | 唯一键 | 必需列 |
|---|---|---|
| `category_daily_all_<latest>.csv` | `dt + gameid` | `dt,gameid,game_name,content_group,dau,daily_revenue,daily_pay_user_cnt,arppu,avg_view_mins,attribution_user_cnt,live_anchor_cnt,group_live_anchor_cnt,total_live_anchor_cnt` |
| `anchor_weekly_guild_<start>_<end>.csv` | `week_start + gameid + guild_name + luid` | `week_start,gameid,game_name,content_group,guild_name,luid,roomid,snick,dau_sum,revenue_sum,pay_sum,live_sum,acu_sum,acu_days,view_sum,view_days,attribution_sum,interaction_cnt_sum,interaction_user_sum,live_days` |
| `anchor_daily_focus_<start>_<end>.csv` | `dt + luid` | `dt,gameid,content_group,guild_name,luid,snick,roomid,dau,daily_revenue,daily_pay_user_cnt,is_live,live_mins,avg_acu,avg_view_mins,attribution_user_cnt,interaction_cnt,interaction_user_cnt` |
| `event_user_revenue_<start>_<end>.csv`（可选） | `dt + gameid + guild_name + luid + user_event_type` | `dt,week_start,gameid,game_name,content_group,guild_name,luid,snick,user_event_type,revenue,pay_user_cnt` |
| `platform_daily_<start>_<end>.csv`（启用日报时必需） | `dt` | `dt,platform_dau` |

CSV 使用 UTF-8 或 UTF-8 with BOM。`luid`、`roomid` 和所有长 ID 必须按字符串保存，禁止科学计数法。关键日期、品类、主播 UID 不得为空。字段名不得自行翻译、重命名或合并。

每次构建输出到新的运行目录，至少包含：

- `dashboard_data_<run>.json`
- `ecology_dashboard_<run>.html`
- `validation_report_<run>.json`
- `browser_smoke_report_<run>.json`（使用 `--smoke-test` 时）
- `run_manifest_<run>.json`
- `accuracy_reconciliation_<run>.md`（源表独立复算记录）
- `daily_alert_report_<run>.html`、`.json`、`.md`（启用日报时）
- `daily_alert_smoke_report_<run>.json`、`daily_alert_manifest_<run>.json`（启用日报时）

## 完整刷新流程

### 1. 确定快照和执行 SQL

优先使用本 skill 中的生产 SQL：

- `assets/sql/core/01_全品类日级趋势.sql`：全平台、内容大类和全品类日级数据，同时输出品类、内容大类和平台有开播主播数。
- `assets/sql/core/02_主播周归因与公会.sql`：主播周归因、公会和层级分析，同时输出每个主播的开播天数。
- `assets/sql/core/03_主播日级专项追踪.sql`：单主播日级专项追踪，同时输出当天是否开播。
- `assets/sql/core/04_赛事用户支付属性_优化版_未产出.sql`：赛事支付属性，只有验证产出后才可使用。
- `assets/sql/core/06_平台日活趋势.sql`：官方平台 DAU，按 `user_ukey` 日级去重；启用日报时必须执行并导出 `dt,platform_dau`。

执行前用源表确认最新分区：

```sql
SELECT max(dt) AS latest_dt
FROM zhgametemp.zty_category_ecology_health_daily_d_i_0827_v1
WHERE dt BETWEEN '<current_start>' AND '<current_end>';
```

实际取数止期以该结果为准。SQL 默认先用 Presto；Presto 不兼容时再改为 Spark，并记录最终执行引擎。日期范围、筛选条件、内容大类映射和指标拆分必须与 SQL 源文件一致。

赛事 CSV 只有在以下条件全部满足时才标记 `ready`：SQL 已成功执行、目标期行数大于 0、支付与观时窗口完整、`dt/week_start/gameid/guild_name/luid/user_event_type` 唯一。否则标记 `pending`，不得推断为 0。

### 2. 导出并接收 CSV

把四类 CSV 放入独立交接目录。接收方先检查文件名、周期和内容一致，再计算 SHA-256：

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath '<file.csv>'
```

发送方和接收方的哈希必须一致。哈希不一致视为传输损坏，重新传输，不尝试修补。

### 3. 执行输入结构检查

在运行构建前检查：

- 文件存在、非空、UTF-8 可读、中文无乱码。
- header 与上表完全匹配。
- 三个核心唯一键无重复。
- `week_start` 全部为周一，升序排列且相邻恰好 7 天。
- 主播日表日期落在主播周表覆盖区间内。
- 品类日表和主播周表的日期范围与运行清单声明一致。
- 长 ID 仍是字符串，不是 `1.23E+09`。

任一项失败必须回到取数或导出步骤，不能依赖构建脚本“容错”。

### 4. 执行源表独立准确性复算

这是发布硬门槛。准确性不能只检查 JSON 自洽，必须从源表用独立查询重新计算，并与 CSV 抽样或聚合结果对账。至少执行以下四组检查，并按 [references/accuracy-reconciliation-template.md](references/accuracy-reconciliation-template.md) 把 SQL、查询结果、差异和结论写入 `accuracy_reconciliation_<run>.md`。

1. 日期覆盖：核对源表最小/最大 `dt`、目标分区是否存在、缺失日期列表；不得把“分区不存在”当成指标为 0。
2. 品类日表：按日期独立重算 `category='品类整体'` 的总行数、品类数和核心指标。至少抽取 3 个日期，每个日期核对总盘、游戏、娱乐（秀场）、娱乐（非秀场）和 3 个头部品类；同时核对 `live_anchor_cnt/group_live_anchor_cnt/total_live_anchor_cnt`。
3. 主播周表：按 `week_start` 独立重算 `category='主播明细'` 的主播数、公会数和 `dau_sum/revenue_sum/pay_sum/attribution_sum/interaction_user_sum/live_days`。至少核对 3 个周期、3 个公会、5 个主播。
4. 主播日表：按 `dt + luid` 独立重算至少 3 个主播、3 个日期的 `dau/daily_revenue/daily_pay_user_cnt/attribution_user_cnt/interaction_user_cnt/is_live`；确认专项筛选条件与 input contract 一致。

推荐的独立复算骨架如下；实际字段必须沿用生产 SQL，不得为了验证另造口径：

```sql
-- 品类日表：按日期和内容大类复算
WITH game_dim AS (
    SELECT cast(game_id AS varchar) AS gameid,
           max(game_label) AS game_label
    FROM gamelive.dim_huya_game_d_a
    GROUP BY cast(game_id AS varchar)
), typed AS (
    SELECT h.dt,
           CASE
               WHEN g.game_label = '游戏' THEN '游戏'
               WHEN g.game_label = '娱乐' AND h.gameid IN ('1663','2165','4079') THEN '娱乐（秀场）'
               WHEN g.game_label = '娱乐' THEN '娱乐（非秀场）'
               ELSE '未匹配'
           END AS content_group,
           h.dau,
           h.daily_revenue,
           h.daily_pay_user_cnt,
           h.attribution_user_cnt
    FROM zhgametemp.zty_category_ecology_health_daily_d_i_0827_v1 h
    LEFT JOIN game_dim g ON h.gameid = g.gameid
    WHERE h.dt BETWEEN '<start>' AND '<end>'
      AND h.category = '品类整体'
)
SELECT dt,
       content_group,
       sum(dau) AS dau,
       sum(daily_revenue) AS daily_revenue,
       sum(daily_pay_user_cnt) AS daily_pay_user_cnt,
       sum(attribution_user_cnt) AS attribution_user_cnt
FROM typed
GROUP BY dt, content_group
ORDER BY dt, content_group;
```

```sql
-- 主播周表：按周、品类、公会和主播复算
WITH anchor_day_info AS (
    SELECT dt,
           cast(gameid AS varchar) AS gameid,
           cast(ayyuid AS varchar) AS luid,
           max(nullif(trim(cast(cname AS varchar)), '')) AS cname,
           max(coalesce(com_cnt, 0)) AS interaction_cnt,
           max(coalesce(com_ucnt, 0)) AS interaction_user_cnt
    FROM gamelive.dm_huya_ayyuid_detail_day
    WHERE dt BETWEEN '<start>' AND '<end>'
      AND ayyuid IS NOT NULL
      AND trim(cast(ayyuid AS varchar)) NOT IN ('', '0', '-1')
    GROUP BY dt, cast(gameid AS varchar), cast(ayyuid AS varchar)
), daily AS (
    SELECT cast(h.dt AS date) AS dt,
           cast(h.gameid AS varchar) AS gameid,
           cast(h.luid AS varchar) AS luid,
           coalesce(nullif(a.cname, ''), '无公会') AS guild_name,
           h.dau,
           h.daily_revenue,
           h.daily_pay_user_cnt,
           h.attribution_user_cnt,
           coalesce(a.interaction_user_cnt, 0) AS interaction_user_cnt
    FROM zhgametemp.zty_category_ecology_health_daily_d_i_0827_v1 h
    LEFT JOIN anchor_day_info a
      ON h.dt = a.dt
     AND h.gameid = a.gameid
     AND h.luid = a.luid
    WHERE h.dt BETWEEN '<start>' AND '<end>'
      AND h.category = '主播明细'
      AND h.luid IS NOT NULL
      AND trim(h.luid) NOT IN ('', '0', '-1')
      AND coalesce(trim(h.snick), '') NOT LIKE '#%'
      AND coalesce(trim(h.snick), '') <> '未归属主播'
)
SELECT date_format(date_trunc('week', d.dt), '%Y-%m-%d') AS week_start,
       d.gameid,
       d.guild_name,
       d.luid,
       sum(d.dau) AS dau_sum,
       sum(d.daily_revenue) AS revenue_sum,
       sum(d.daily_pay_user_cnt) AS pay_sum,
       sum(d.attribution_user_cnt) AS attribution_sum,
       sum(d.interaction_user_cnt) AS interaction_user_sum
FROM daily d
GROUP BY date_format(date_trunc('week', d.dt), '%Y-%m-%d'), d.gameid, d.guild_name, d.luid
ORDER BY week_start, d.guild_name, d.luid;
```

准确性通过条件：

- 行数、主播数、品类数、公会数和日期集合与独立复算一致。
- 整数人数、UID、RoomID、日期和周起点完全一致。
- 金额、时长、ACU 等浮点指标按 CSV 精度对账；默认绝对误差不超过 `0.01`，有明确源精度时可使用更严格阈值。
- 每个抽样节点必须给出“源表值、CSV 值、差异、结论”，不能只写“已核对”。
- 当前期与对比期都要检查，不能只验证当前期。
- 抽样必须覆盖总盘、头部和尾部；不能只挑最容易对上的记录。
- 开播主播数必须从 `category='主播明细' AND is_live=1` 的 `luid` 去重结果核对；`live_anchor_cnt <= group_live_anchor_cnt <= total_live_anchor_cnt`，主播周表 `live_days` 必须在 0–7 之间。

若源表在导出后发生回刷，必须固定并记录导出快照；无法固定快照时，重新导出一份并整套复算，不能把快照差解释成“正常波动”。

### 5. 构建 JSON 和 HTML

在 skill 目录执行：

```powershell
python scripts/refresh_dashboard.py `
  --category-csv '<category.csv>' `
  --anchor-weekly-csv '<anchor_weekly.csv>' `
  --anchor-daily-csv '<anchor_daily.csv>' `
  --template 'assets/dashboard_template_multidim.html' `
  --output-dir '<new_run_dir>' `
  --run-name '<YYYYWww>' `
  --source-latest-partition '<YYYY-MM-DD>' `
  --daily-report `
  --platform-daily-csv '<platform_daily.csv>' `
  --smoke-test
```

有赛事 CSV 时增加 `--event-csv '<event.csv>'`。脚本从品类日表推导数据日期范围，从主播周表推导周列表；不要手工修改脚本常量。默认拒绝覆盖运行目录中的已有输出，确认是全新运行名后再执行。

启用日报时必须在同一命令中传入 `--daily-report --platform-daily-csv '<platform_daily.csv>'`。平台 DAU 不得用品类 DAU 汇总替代。

### 6. 执行自动数据核验

`refresh_dashboard.py` 会自动运行 `verify_dashboard_package.py`。必要时可独立重跑：

```powershell
python scripts/verify_dashboard_package.py `
  --data '<dashboard_data.json>' `
  --report '<validation_report.json>'
```

`validation_report_<run>.json` 必须同时满足：

- `status = passed`。
- `topLevelSchema = true`。
- `dateFormat = true`，所有日期可解析。
- `consecutiveWeeks = true`，周起点连续且间隔 7 天。
- `categoryUniqueKeys = true`、`anchorWeeklyUniqueKeys = true`、`anchorDailyUniqueKeys = true`。
- `indexRanges = true`，所有索引都能映射到有效的周、品类、公会和主播。
- `diagnosticCountsMatch = true`，metadata diagnostics 与实际数组行数完全一致。
- `searchCoverage = true`，主播昵称覆盖率 `>= 99%`，RoomID 覆盖率 `>= 90%`。
- `finiteNumbers = true`，不存在 NaN 或 Infinity。
- `eventStatusConsistent = true`：`pending` 时赛事行为 0；`ready` 时赛事行数大于 0。
- `liveAnchorCountsValid = true`：品类/内容大类/平台开播主播数满足包含关系，主播 `live_days` 在 0–7，主播日 `is_live` 仅为 0/1。
- `nonEmptyCoreData = true`，三类核心数据均非空。

启用日报时，`refresh_dashboard.py --daily-report` 会在主看板验证后继续调用 `build_daily_alert_report.py`。日报固定包含平台 DAU、打赏流水、打赏人数、归属用户数、开播主播数，过去 4 个相同星期中位数基线，以及品类榜、公会榜、主播层级和主播榜。品类、公会、主播榜默认分别为 Top10、Top20、Top10，页面内均可自定义展开 1–50 名；JSON 只内嵌各榜前 50 行。分析范围仅保留平台 DAU 与内容生态 DAU，内容大类和品类必须通过独立下钻控件选择。

`daily_alert_report_<run>.json` 的以下检查必须全部为 `true`：

- `reportDateAvailable`、`baselineDatesEnough`、`categoryRowsPresent`。
- `platformDauAvailable`：官方平台 DAU 在日报日期和基线日期均有值。
- `weeklyComparisonAvailable`：至少有当前和上一个完整自然周。
- `sourceValidationPassed`：输入的主看板 `validation_report` 为 `passed` 且全部检查为 `true`。
- `topTablesPopulated`、`visualizationDataAvailable`、`categoryContributionBounded`、`anchorVisualizationAvailable`、`htmlContainsCoreSections`、`allNumbersFinite`。零基线变化率必须返回空值，不得写入 Infinity。
- 启用浏览器检查时 `browserSmokePassed=true`。

平台 DAU 下降且开播主播数显著下降时才提示供给问题；开播主播数轻微波动不得生成“供给减少”的强结论。品类、公会、主播贡献率必须保留正负方向，贡献分母使用变化绝对值，不能因根节点为负而把跌幅显示成正贡献。

同时检查 diagnostics 和 warnings：

- `categoryDailyRows`、`categoryCount`、`anchorWeeklyRows`、`anchorCount`、`guildCount`、`anchorDailyRows`、`eventDailyRows`、昵称覆盖率和 RoomID 覆盖率必须写入运行记录。
- `interactionOverDauRows > 0` 属于警告，不自动判失败；原因是互动人数跨场次/主播未全量去重。该指标只能做相对趋势，不能当成全站去重人数。
- 全平台 DAU 与源表总盘对账后，若量级明显异常，必须回到 `category='品类整体'` 过滤和维度索引检查。主播明细 DAU 不得汇总成平台 DAU。
- 月份跨周不完整时，环比、贡献值和趋势桶必须显示“数据不足”，不能按 0 处理。

### 7. 执行浏览器冒烟

构建命令带 `--smoke-test` 后会生成 `browser_smoke_report_<run>.json`。以下四项必须全部为 `true`：

- `processExitZero`
- `dashboardTitleRendered`
- `rankingRendered`
- `loadingCleared`

单独重跑命令：

```powershell
node scripts/smoke_test_dashboard.mjs `
  --html '<ecology_dashboard.html>' `
  --report '<browser_smoke_report.json>'
```

如果本机没有 Chrome/Edge 或 Node.js，报告必须写“浏览器冒烟未执行”，不得把静态检查描述成全流程通过。

### 8. 人工交互验收

自动冒烟通过后，打开生成的 HTML 并至少抽查：

1. 首屏总盘卡片与当前期/对比期一致。
2. 日/周/月/季/年和自定义时间切换正常。
3. 内容大类、品类、公会、主播层级、主播可自由增删、排序和逐层下钻。
4. Top20 在每次对比期与当前分层下按贡献正确重算；单主播搜索后不显示多层复层表。
5. UID、RoomID、昵称和模糊词搜索能列出候选；同名词不会串主播。
6. 总盘、内容大类、全品类和主播专项的 DAU、归属用户、流水、互动人数、互动率可读且口径提示存在。
7. “开播主播数”可按时间切换，且首屏 KPI、趋势和单层/复层表都能显示。
8. 赛事状态为 `pending` 时赛事筛选被禁用或明确提示；不能静默显示 0。
9. 主看板和日报均使用浅色液态玻璃视觉，正文与表格对比度足够；不得只在局部页面应用。
10. 两个自由分析画布默认展示大盘 DAU 趋势，可切换日/周/月/季度，支持折线、柱状和 100% 堆积；日报支持模糊搜索并同时选择最多 8 个内容大类、品类或异动 Top50 主播进行对比，也可用预设天数或自定义开始/结束日期限定时间范围。悬停应显示时间桶和具体数值 Tooltip。
11. 日报所有周期标签必须写清“日/周/月”等口径，例如“平台 DAU（日）”和“最新完整周 DAU（7 日求和）”。
12. 移动端无关键控件遮挡、页面级横向溢出或无法展开；表格自身可以横向滚动。
13. 日报分析范围只能包含平台 DAU 和内容生态 DAU；内容大类、品类位于下钻维度。品类、公会、主播榜默认分别为 Top10、Top20、Top10，均支持 1–50 自定义；公会榜主指标为开播主播数日均，层级阈值和灰色口径说明位于页面下方。
14. 主播榜必须显示“级别”列，并按每一行主播路径自身前 4 个完整周 DAU 的中位数、MAD 和异常分判定；缺周不得补 0，历史不足 4 周时按低把握降级。
15. 公会榜必须显示“级别”列，并按公会自身前 4 个完整周开播主播数日均的中位数、MAD 和异常分判定；跨品类必须先按公会+主播去重，再使用去重后的 `live_days / 7`。缺周不得补 0，历史不足 4 周时按低把握降级。
16. 日报自定义日期必须限制在当前数据实际可用区间；主播维度应使用主播日表覆盖区间，不得把未覆盖日期补 0。品类表上线前必须检查所有 `contributionShare` 落在 -100% 至 100%，且绝对值之和接近 100%。

开发模板或画布交互时可运行以下回归检查：

```powershell
node scripts/test_dashboard_template.mjs
python -m unittest scripts/test_daily_alert_visualization.py -v
node scripts/test_dashboard_multidim.mjs '<ecology_dashboard.html>'
node scripts/test_daily_alert_visualization.mjs '<daily_alert_report.html>'
```

两个浏览器交互脚本需要可用的 Chrome 调试端口，并会把指定 HTML 导航到当前调试页。主看板脚本验证维度增删排序、复层下钻、主播搜索和全粒度趋势；日报脚本验证默认平台日趋势、柱状、平台及内容生态 100% 堆积、内容大类下钻和月粒度。任一失败都不得发布。

### 9. 检查运行清单并发布

`run_manifest_<run>.json` 必须包含：

- `runName`、`status`、`sourceLatestPartition`。
- 品类数据起止日期、主播周列表。
- 四类输入行数（赛事缺失时 eventInput 为 0）。
- 所有输入和输出的绝对路径、字节数、SHA-256。
- 构建、验证、浏览器冒烟命令。
- 嵌入的 validation 和 browserSmokeTest 结果。

发布前重新计算 HTML、JSON 和报告哈希，与 manifest 一致。覆盖正式成品前必须取得用户明确许可；先保留上一版完整副本，再替换，并记录旧版路径。无法恢复的覆盖操作禁止执行。

## 失败、停止和回滚

| 条件 | 必须动作 |
|---|---|
| 缺日期、缺周或周起点不是周一 | 停止；重新取数，不插值、不补 0 |
| 最新分区晚于实际数据 | 写明实际止期后再判断周期是否完整 |
| source/CSV 抽样对不上 | 停止发布；回查 SQL、过滤、粒度、单位、快照和导出 |
| 唯一键重复 | 停止；定位 join 放大或聚合粒度错误 |
| 昵称或 RoomID 覆盖不足 | 停止；补齐主播维表或修正 ID 字符串 |
| 开播主播数包含关系或 live_days 不合法 | 停止；回查 `is_live/luid` 去重与主播日表聚合 |
| 赛事 CSV 缺失或为空 | `eventStatus=pending`，保留字段并禁用赛事筛选 |
| 互动人数大于 DAU | 保留并告警；说明跨场次未全量去重，不强行截断 |
| 月度覆盖不足 | 显示“数据不足”，不计 0、不算环比和贡献 |
| 自动数据校验失败 | 不发布；修复后生成新运行名 |
| 浏览器冒烟失败或未执行 | 不声称全流程通过 |
| manifest 哈希不一致 | 视为文件损坏或版本混淆；重新构建或重新传输 |
| 正式发布后发现问题 | 用发布前副本回滚，并保留失败运行记录 |
| 官方平台 DAU 缺失或未覆盖基线日期 | 日报停止发布；补跑平台日活 SQL，不得用品类合计冒充全站 DAU |
| 日报检查失败 | 保留旧日报和看板；修复后使用新运行名重跑 |

## 核心口径

### 时间与对比

- 当前期日均：当前期有数据日期的指标自然日均。
- 对比期日均：同一指标在对比期的自然日均。
- 绝对变化：当前期日均 - 对比期日均。
- 变化率：绝对变化 / 对比期日均；分母为零或两侧覆盖不一致时不计算。
- 周级数据用于非整周比较时，必须标记为覆盖周近似；缺周显示“数据不足”。

### 指标

- 观看 DAU：`dau` 的日均。
- 平台 DAU：官方平台活跃用户表中 `count(distinct user_ukey)`，端范围为 `huya_andriod/huya_ipad/huya_pad/huya_ios/hmos_kiwi`（鸿蒙），剔除黑名单用户；用于日报平台总盘，不得用品类 DAU 合计替代。
- 归属 DAU：`attribution_user_cnt` 的日均。
- 打赏流水：`daily_revenue / revenue_sum` 的日均。
- 打赏人数：`daily_pay_user_cnt / pay_sum` 的日均。
- ARPPU：打赏流水 / 打赏人数，不能用分组 ARPPU 简单平均。
- 人均观时：`avg_view_mins` 在有观看记录日期的平均。
- 互动人数：`interaction_user_cnt` 的日均。
- 互动率：互动人数 / 观看 DAU。
- 开播主播数：周期内每日 `is_live=1` 的 `luid` 去重数再取日均。品类、内容大类和平台使用日级精确去重；公会、层级和主播使用 `live_days / 7`，跨品类时按主播周去重。
- 主播 ACU：`acu_sum / acu_days`。
- 主播层级：运行窗口整体平均 ACU；头部 `>=2000`，腰部 `100–1999.999…`，尾部 `<100`。
- 公会：`gamelive.dm_huya_ayyuid_detail_day.cname`，空值为“无公会”。

### 贡献与 Top N

- 节点日均变化 = 当前期日均 - 对比期日均。
- 父层贡献率 = 节点日均变化 / 直接父路径日均变化。
- 总盘贡献率 = 节点日均变化 / 全平台根节点日均变化。
- 负向拖累按变化值升序；正向拉动按变化值降序；综合贡献按绝对值降序。
- 每层 Top N 必须根据当前对比期、当前指标和当前筛选范围动态计算，不得在源码中固定名单。
- 日报品类、公会、主播榜默认分别为 Top10、Top20、Top10，均支持 1–50；先保留最多 50 行候选，再由前端按用户输入截断。
- 日报品类贡献占比 = 品类 DAU 日均变化 / 全部品类 DAU 日均变化绝对值之和。分母不使用可能接近零的大盘净变化，避免贡献率被放大到数千百分比。

### 内容大类

- 游戏：`game_label='游戏'`。
- 娱乐（秀场）：`game_label='娱乐'` 且 gameid 为 `1663/2165/4079`。
- 娱乐（非秀场）：其余 `game_label='娱乐'`。
- 未匹配：无法从最新品类维表匹配。

### 不可直接相加

- 各品类 DAU、归属用户和互动人数可能跨品类重叠，总和不是全站去重用户。
- 主播观看 DAU 是主播/场次口径，不能汇总成全平台 DAU。
- 互动人数跨场次、主播、公会可能重叠；互动率只用于相对监控和异常发现。
- 不同路径下主播和用户可能重复，多层明细各行人数不能直接相加。

## 资源

- 详细字段与交接契约：[references/input-contract.md](references/input-contract.md)
- 源表准确性复算记录模板：[references/accuracy-reconciliation-template.md](references/accuracy-reconciliation-template.md)
- 指标、贡献值和不可加总口径：[references/metric-definitions.md](references/metric-definitions.md)
- 补充验收清单：[references/validation-checklist.md](references/validation-checklist.md)
- SQL 来源与使用边界：[references/sql-catalog.md](references/sql-catalog.md)
- 当前生产 SQL：`assets/sql/core/`
- 历史与赛事参考 SQL：`assets/sql/reference/`
- 数据构建：`scripts/build_dashboard_data_multidim.py`
- HTML 注入：`scripts/build_dashboard.py`
- 数据验证：`scripts/verify_dashboard_package.py`
- 一键刷新：`scripts/refresh_dashboard.py`
- 无头浏览器冒烟：`scripts/smoke_test_dashboard.mjs`
- 异动日报：`scripts/build_daily_alert_report.py`
- 看板模板：`assets/dashboard_template_multidim.html`
- 日报自由画布：`assets/daily_alert_visualization.js`
- 模板与日报画布测试：`scripts/test_dashboard_template.mjs`、`scripts/test_daily_alert_visualization.py`、`scripts/test_daily_alert_visualization.mjs`
