# SQL 资源目录

## 当前生产

### `assets/sql/core/01_全品类日级趋势.sql`

- 用途：全平台/内容大类/品类日趋势。
- 粒度：`dt + gameid`。
- 主表：`zhgametemp.zty_category_ecology_health_daily_d_i_0827_v1`，`category='品类整体'`。
- 维表：`gamelive.dim_huya_game_d_a`。
- 刷新时更新日期范围和维表最新分区。

### `assets/sql/core/02_主播周归因与公会.sql`

- 用途：主播周归因、公会、层级和互动。
- 粒度：`week_start + gameid + guild_name + luid`。
- 主表：健康日表 `category='主播明细'`。
- 补充：`dm_huya_ayyuid_detail_day` 的昵称、公会、RoomID、评论数和评论人数。
- 刷新时更新两个源表日期区间。

### `assets/sql/core/03_主播日级专项追踪.sql`

- 用途：单主播日级专项趋势与搜索后的精细追踪。
- 粒度：`dt + gameid + luid`。
- 刷新时与周表使用相同日期范围。

## 待验证/待回刷

### `sql/templates/赛事品类登记日.sql` 与 `sql/templates/赛事单周期统计.sql`

- 用途：V1.2 赛事剔除视图。按单赛事周期日均 DAU 筛选大赛事，并剔除品类相对下限以下的异常低赛事。
- 输出：登记日模板输出 `dt + gameid + match_id`；单赛事统计模板输出 `gameid + match_id + observed_days + mean_event_dau`。
- 执行：替换快照、起止日期后使用 Presto；运行 `build_major_event_days.py` 生成 `major_event_days.csv` 和 `major_event_manifest.json`，再传入 `build_daily_v12.py --event-days --event-meta`。
- 历史 `赛事品类前10赛事日.sql` 已废弃，仅用于复盘；不得用于新运行。
- 限制：版权表未覆盖品类表示赛事覆盖未知，不是非赛事；该规则不是官方赛事窗口或因果净效应。

### `assets/sql/core/04_赛事用户支付属性_优化版_未产出.sql`

- 用途：给游戏支付用户标记支付日前 90 天赛事观时占比。
- 当前状态：SQL 已写，尚未形成有效 CSV，不能用“产物通过”描述。
- 只有回刷并通过用户数、金额、日期覆盖和 join 放大验证后，才能把 `eventStatus` 改为 `ready`。

### `assets/sql/core/05_赛事用户支付属性_初版_参考.sql`

- 与优化版同口径的初版，保留用于 diff 和性能对照。生产优先优化版，不能盲目二选一混用。

## 历史参考，不是生产查询

`assets/sql/reference/` 中：

- `01` 是赛事日与赛事用户口径参考。
- `02–05` 是旧周报固定日期/固定品类版本。
- `06–09` 是分品类、Top20 和剔除赛事日的历史分析参考。

使用这些文件时先核对日期、源表、维表和字段拆分；旧版“平台活跃 DAU”不能替代当前健康日表的品类整体口径。
