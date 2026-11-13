# APP直播间进入与全屏按钮点击

2026-11-12，用户已确认按yyuid去重，APP范围沿用source/特定主播By月去重DAU/世界杯数据整合/用户点击事件口径.sql。原指定Desktop/SQL路径不存在，参考迁移归档。

- 进入：pageview/liveroom；点击：click/verticallive/fullscreen，截图名称“点击/竖屏直播间/全屏按钮”。不证明实际屏幕旋转。
- APP：huya_andriod、huya_ios、huya_ipad、huya_pad、hmos_kiwi。跨端按UID去重，不相加分端人数。
- main.sql为UID标志主路径；independent.sql为直接count distinct独立路径；sample.sql为5用户重复事件检查。
- 时间：源dt和stime同时限定2026-11-12自然日。排除NULL/空/0/-1 UID，不额外推定登录态。
- 结果：进入2,886,207；点击1,570,641；交集1,560,939（无先后限制）；仅点击9,702。
- iPad点击和安卓平板两个目标事件无上报，不等同真实行为为零。
- 仅归档可复用SQL、汇总与验收证据；本机加密凭据、用户明细和来源映射不入库。

详见validation.md。English: README.en.md。

补充：不限制ety的全量检查（RID1241320559786855936）仅观察到custom_event，截图事件行数与原查询一致；ety限制未漏计该事件。同类检索另发现usr/click/fullscreenbutton、click/minilive/fullscreen，未验证与目标动作等价，不合并。1570641仅指截图事件，不代表所有横屏放大操作。详见validation.md。
