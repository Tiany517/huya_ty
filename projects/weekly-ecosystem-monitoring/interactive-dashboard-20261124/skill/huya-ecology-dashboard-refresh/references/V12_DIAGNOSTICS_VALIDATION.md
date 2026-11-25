# V1.2 诊断与下钻改进验收

## 本轮范围

摘要由长段落改为结果单值单格、过程判断、折叠证据。对象详情由散列卡片改为8项过程指标表，每项展示比较、差异、独立父级贡献、异常分与等级。下一层可选内容大类、公会、层级、主播和版权属性；不强制维度顺序。搜索候选默认6项，搜索最多展示12项，最多比较8对象；维度排序移入折叠设置。下钻明细默认展开，TopN与排序不改变完整父级分母。

## 数据问题与处置

用户截图的4848%可由不可变周导出直接复现：匿名样本当前周观看用户日98、付费用户日4751；上一周分别57225、6737。不是百分比重复乘100。原SQL对健康表主播明细的dau、daily_pay_user_cnt分别求和；上游两指标的样本/端范围是否相同尚未核验。禁止根据此数据解释打赏转化。

新增payRate不变量闸门：任一基础日/周路径出现付费用户日大于观看用户日或负值，该对象整窗比率无效，不删除坏行后计算、不截断到100%、不改动原始导出。当前值、比较值分别保留失败原因；差异、贡献不输出。数学闸门通过不等于源表语义通过，合法范围内的比率仍为探索性、评级待校准。

异常分缺失区分待校准、历史样本不足与周期不支持；数值缺失说明本期/比较期日期不完整、零分母或口径异常。过程证据必须匹配对象、维度、路径、本期和比较期，不用全站或其他周替代；公会周供给仅近似，不认定为精确供给归因。互动率仍封锁，互动人数合计变化不等于承接能力变化。赛事周期未排除。

## 验证证据

- 引擎与12项筛选检查通过；新增坏行反例覆盖本期、比较期及好坏混合日期，不输出伪比率。
- 生成页面DOM回归通过：同对象同周期证据、对象过程表、可选公会下钻、贡献/异常分列、紧凑候选及截图真实样本拦截。
- 独立导出对账8项通过（六项品类字段全量、原周/日明细），Python与JS周聚合50项精确对账。
- 浏览器预览09已实查品类王者荣耀过程表、公会/主播下钻和贡献/异常分；宽屏1280与默认窄屏检查，表格横向滚动。截图问题比率显示口径异常。预览10增加缺分原因文本和子表排序，最终DOM回归通过；真实浏览器再验王者过程表、主播子表本期值排序，结果按本期值降序变化。
- 未执行：全历史源表重跑、异常付费与观看共同cohort独立核验、完整大赛事周期认定、全部维度全浏览器测试；不标记整个V1.2正式通过。

## 交付和回滚

构建输出独立目录v12-preview-10；桌面保存带版本的新HTML，不覆盖原始数据与旧日报。输入与产物哈希见构建清单。旧预览09保留以便比对。

GitHub远端2026-11-25再次查询isPrivate=false；依用户要求私有数据不得推送公开仓库。只提交代码、测试与本文，不提交CSV、JSON、内嵌业务HTML或原始主播明细。

English: Evidence-led diagnostics and arbitrary child attribution are implemented. Invalid pay-rate source paths invalidate the entire object window rather than being dropped or clipped. Null ratings distinguish uncalibrated metrics and insufficient history. Export reconciliation is not warehouse semantic acceptance. Tournament-cycle diagnosis and full historical source validation remain pending. Public remote prevents pushing this business project.
