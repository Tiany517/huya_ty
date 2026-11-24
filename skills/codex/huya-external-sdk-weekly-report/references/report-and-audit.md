# Report, Validation, and Attribution

## Metric definitions

- “本周” means the latest completed Monday-Sunday window.
- “上周” means the immediately preceding Monday-Sunday window.
- `周日均DAU = 非零日DAU合计 / 非零天数`.
- Exclude zero values independently in both weeks and for each platform.
- A zero in an existing partition is an anomalous metric value. A missing partition is missing data and must not be converted to zero.
- Compute week-over-week percentage from unrounded averages.
- Mark `（稳定）` only when `abs(current / previous - 1) < 0.03`.

## Mandatory validation

1. Both sources cover both Monday-Sunday windows. The latest partition is at least the report-week end.
2. The daily platform grain is `dt`; the anchor-day grain is `dt + userid`, with no unexpected duplicate keys after aggregation.
3. Each platform’s prior and current non-zero day counts are recorded.
4. Numerator and denominator use the same non-zero dates.
5. The sign and displayed rounding of every percentage match the unrounded calculation.
6. The stable label is generated from the threshold, never copied from an older report.
7. If anchor attribution is performed, the sum of all anchor contribution changes exactly reconciles to the video-level daily-average change within rounding tolerance.
8. Gross declines, gross increases, and net change are all reported during validation so that shares cannot be misinterpreted.

## Attribution rules

For an anchor in a seven-day window:

```text
weekly contribution = sum of anchor daily DAU / 7
contribution delta  = current weekly contribution - previous weekly contribution
overall video delta = sum of all anchor contribution deltas
```

To explain a contribution delta when the anchor has live-day and per-live-day DAU metrics:

```text
DAU per live day = weekly contribution * 7 / live days
```

Use the previous-week per-live-day DAU as the decomposition baseline:

```text
live-day effect      = (current live days - previous live days) * previous DAU per live day / 7
per-live-day effect  = current live days * (current DAU per live day - previous DAU per live day) / 7
total contribution delta = live-day effect + per-live-day effect
```

State the chosen baseline when presenting a decomposition. Do not describe an observed traffic or scheduling change as a proven cause without supporting evidence.

## Share calculations

Use net-change share when explaining the final report:

```text
anchor share of net decline = anchor contribution delta / overall video delta
```

也同时计算全部下降主播降幅占比：

```text
主播占全部降幅 = |主播贡献变化| / Σ|所有下降主播贡献变化|
```

两个分母回答不同问题：前者衡量对最终净变化的解释力度，后者衡量在该主播在全部下跌中的占比。报告中必须注明分母。净变化占比可以超过100%，因为上升主播会抵消部分下降。

## Executive report template

```text
仇总上周外部SDK数据如下：

1. 视频号本周环比X%，本周DAU为Xw，[仅在存在重大异常时补充一句类别级原因，例如“主要受头部棋牌主播开播天数下降影响”]；
2. 先锋本周环比X%（稳定），本周DAU为Xw；
3. 微软本周环比X%（稳定），本周DAU为Xw；
4. QQ浏览器本周环比X%，本周DAU为Xw，[有业务依据时保留产能说明]；
5. 应用宝本周环比X%（稳定），本周DAU为X。
```

方括号中的内容仅用于指导，不应原样发给老板。只有存在重大异常时才补充原因，并且只写有数据支持的类别级结论。

视频号异常归因在内部至少检查以下维度：

- 日均开播主播数、总开播主播数、新增和退出主播数量
- 主播开播天数、人均开播天数、开播总时长、人均日均开播时长
- 单日DAU、每个开播日的DAU、每个开播小时的DAU
- 下降主播合计、上升主播合计、净变化和头部主播贡献占比
- 头部主播所属品类及品类级增减贡献
- 主播贡献合计与视频号总量的精确对账

只有这些维度仍不能解释时，再考虑查询开播时段、内容变化、推荐曝光、流量来源或同品类对照。不要根据主播名称或单一指标直接推断原因。

如果确认视频号变化主要由主播驱动，除五段式老板版报告外，必须附主播归因明细表。默认列出贡献降幅绝对值最大的前5名主播，字段包括：

| 主播名称 | 上周7天DAU合计 | 本周7天DAU合计 | 上周周均DAU贡献 | 本周周均DAU贡献 | 贡献变化 | 上周开播天数 | 本周开播天数 | 开播天数变化 | 上周日均开播时长 | 本周日均开播时长 | 上周单日DAU | 本周单日DAU | 占视频号净变化 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|

主播按贡献降幅从大到小排序。DAU单位必须在表头或表下注明，所有数值拆成独立单元格，不使用箭头合并“上周值→本周值”。未开播日期按0计入7天合计；没有开播时日均时长可标记`n.a.`。表格后补充下降主播合计、上升主播合计、整体净变化及对账状态。老板版正文不展开主播名称，但必须附此表供复盘。

Only include `（稳定）` where applicable. Keep the executive report to these five lines. Do not name individual anchors; summarize to a defensible business category when requested. Avoid explaining routine operational facts that do not affect the conclusion.
