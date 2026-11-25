# 指标驱动异动分析与赛事复用工作流

目标：识别赛事之外仍需排查的异动。结论性质为描述与相关，不能认定赛事或供给导致变化。

## 使用流程

1. 先查各源最新分区、字段字典、端覆盖与窗口；保留输入快照，不修改原JSON。
2. BigData优先Presto执行诊断SQL 08/09/10，保存原始返回。重跑时把查询日期、快照和输入目录写入清单，不能照抄本次日期。
3. 拉新/回流以dt/gameid/user_ukey求并集，复算new+return-intersection=union。拉新排除mailiang，上游不含鸿蒙，归因品类不等于实际观看品类。
4. 互动先检查主播日键唯一、join匹配率、分子大于分母数量；未通过语义核验不能发布严格互动率。本次1,291,112键，匹配1,264,481，19,807键分子高于分母。仅保留互动UV合计探索趋势，不给互动率正式贡献和级别。
5. 赛事模板用 `python scripts/render_tournament_template.py --start YYYY-MM-DD --end YYYY-MM-DD --snapshot YYYY-MM-DD --output 新SQL路径` 生成。先验证版权ID映射（含中文ID），再做品类日主播去重、观看用户并集；单赛事分布与品类日并集分布必须分开。
6. 每品类研究P50/P75/P90、赛事观看占比与连续周期。P90只作候选：MSI等重要赛事可能低于P90，必须按赛事完整周期、官方排期和流量强度复核，不以单日标签替代整个周期。无版权记录不等于无赛事，体育等缺覆盖单列。
7. 独立核验至少5个峰值日，用事实表EXISTS半连接从ukey粒度复算，而非复用聚合CTE；核对赛事名单重复、业务日、分区、端、用户并集。固定赛事主播与其他主播应拆成仅赛事名单/仅其他/交集，三者回到品类DAU。
8. 日榜按报告日与前4个同星期中位数；另提供剔除版权登记赛日的同星期对照。后者只排除登记日期，未排除赛后回落、赛期间休赛日及其他活动，不能称为净赛事效应。
9. 周榜变化对上周、级别对自身前4个完整周；指标各自遍历全候选后排名。贡献=对象delta/全候选abs(delta)之和；筛选/TopN不变分母。零分母显示0，缺历史待核验不补零。比率若通过语义核验，用结构百分点桥接，不套UV贡献公式。
10. 构建到新目录，加 `--metric-supplement` 指向3份查询返回目录。运行单测、JS语法与DOM交互测试，检查筛选排序、不同指标独立榜单、时间粒度、缺失断线、占比闭合、输出中文和哈希；浏览器视觉未验收不得标记全流程通过。备份后更新桌面。

## 验收卡（本次）

源/中间/输出唯一键分别为源定义、日品类用户/日品类主播、日品类；周榜为周/对象路径/指标。高风险：跨主播UV重复、端不一致、无登记被误认非赛事、历史期缺失、阈值误当最终标签。

| 核查 | 状态与证据 |
|---|---|
| 可用性 | 查询分区2026-10-01至11-24，各源55天；逐品类完整性仍需核查 |
| Schema语义 | 拉新回流沿用源口径；互动率语义失败，禁止正式发布 |
| 唯一键 | 返回按dt/gameid检查重复；拉新并集恒等式逐行检查 |
| 关联 | 互动键匹配率97.94%；存在分子大于分母，不能当严格比率 |
| 不变量 | 每指标绝对贡献占比合计1（存在非零变化时）；比率未上线 |
| 独立源复算 | 报告日5品类拉新/回流/并集已用FULL JOIN路径逐值对账通过（SQL11，rid 1245683548900036096）；历史各期及互动语义待验证 |
| 边界抽查 | 缺期不补零；源覆盖前日期不填0；人工逐UID抽查未执行 |
| 交付运行 | 构建和单测结果另存运行目录；不得将核心旧检查passed等同补充指标已验证 |

本次补充数据仅供探索。新增互动/拉新/回流阈值为试运行10%与绝对50，异常分规则沿用原分类器，尚未历史回测校准。正式“大赛事”阈值与净归因尚未验收。

English: Metric-first anomaly rankings use full eligible populations and independent metric baselines. Registered-event-day exclusion is descriptive, not causal. Acquisition/return follow upstream four-port attribution; interaction rate is withheld because numerator and denominator semantics fail. New supplementary results remain exploratory until independent source reconciliation and browser acceptance pass.
