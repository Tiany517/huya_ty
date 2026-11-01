// -*- coding: utf-8 -*-
/**
 * AI工坊 App 各版本 × 周 日均转换率
 * 输入：AI工坊_版本天明细_20260713-20260914.csv（Presto 取数，版本 × 天 粒度）
 * 输出：AI工坊_版本周日均转换率_20260713-20260914.xlsx
 * 口径：日均转换率 = 该版本该周内逐日「当日支付人数 ÷ 当日曝光人数」的算术平均
 *       （曝光人数为 0 的天不计入）；周为自然周（周一起 7 天），末周截至 09-14
 */
import fs from "node:fs/promises";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const SRC = "C:/Users/tiany/Desktop/AI工坊专题/AI工坊_版本天明细_20260713-20260914.csv";
const OUT = "C:/Users/tiany/Desktop/AI工坊专题/AI工坊_版本周日均转换率_20260713-20260914.xlsx";

const VERSIONS = ["13.3.82", "13.4.0", "13.4.2", "13.4.22", "13.4.40", "13.4.41", "13.4.52", "13.4.63"];
// 业务确认的版本更新窗口（连续、无重叠，合计覆盖 2026-07-13 ~ 2026-09-14）
const WIN = {
  "13.3.82": ["2026-07-13", "2026-07-19"],
  "13.4.0": ["2026-07-20", "2026-07-26"],
  "13.4.2": ["2026-07-27", "2026-08-06"],
  "13.4.22": ["2026-08-07", "2026-08-10"],
  "13.4.40": ["2026-08-11", "2026-08-20"],
  "13.4.41": ["2026-08-21", "2026-08-30"],
  "13.4.52": ["2026-08-31", "2026-09-07"],
  "13.4.63": ["2026-09-08", "2026-09-14"],
};
const W0 = Date.UTC(2026, 6, 13);
const WEND = Date.UTC(2026, 8, 14);
const DAY = 86400000;

const CN = "楷体";
const EN = "Calibri";
const DARK = "#1F4E78";
const HEAD_FILL = "#DDEBF7";
const THIN = "#BFBFBF";

const csvText = (await fs.readFile(SRC, "utf8")).replace(/^\uFEFF/, "");
const lines = csvText.trim().split(/\r?\n/);
const cols = lines[0].split(",");
const recs = lines.slice(1).map((ln) => {
  const p = ln.split(",");
  const o = {};
  cols.forEach((c, i) => (o[c] = p[i]));
  return {
    dt: o.dt,
    iver: o.iver,
    exp: Number(o.exposure_user_cnt) || 0,
    pay: Number(o.pay_user_cnt) || 0,
    amt: Number(o.ai_amount) || 0,
  };
});

const iso = (ms) => new Date(ms).toISOString().slice(0, 10);
const mmdd = (ms) => iso(ms).slice(5);

const weeks = [];
for (let s = W0; s <= WEND; s += 7 * DAY) {
  const e = Math.min(s + 6 * DAY, WEND);
  weeks.push({ start: s, end: e, label: `${mmdd(s)} ~ ${mmdd(e)}` });
}

const dayRows = recs.map((r) => ({ ...r, t: Date.parse(r.dt + "T00:00:00Z") }));

// 周 × 版本 聚合
const cells = {};
const weekTotals = [];
for (let wi = 0; wi < weeks.length; wi += 1) {
  const w = weeks[wi];
  const inWeek = dayRows.filter((r) => r.t >= w.start && r.t <= w.end);
  const totExp = inWeek.reduce((a, r) => a + r.exp, 0);
  const totPay = inWeek.reduce((a, r) => a + r.pay, 0);
  weekTotals.push({ totExp, totPay, rate: totExp > 0 ? totPay / totExp : null });
  cells[wi] = {};
  for (const v of VERSIONS) {
    const a = inWeek.filter((r) => r.iver === v && r.exp > 0);
    if (a.length === 0) continue;
    const sumExp = a.reduce((s, r) => s + r.exp, 0);
    const sumPay = a.reduce((s, r) => s + r.pay, 0);
    const dailyRates = a.map((r) => r.pay / r.exp);
    cells[wi][v] = {
      days: a.length,
      sumExp,
      sumPay,
      avgDailyRate: dailyRates.reduce((s, x) => s + x, 0) / dailyRates.length,
      cumRate: sumPay / sumExp,
      share: totExp > 0 ? sumExp / totExp : null,
    };
  }
}

const workbook = Workbook.create();

// 版本窗口 × 版本 曝光占比
const winShares = {};
for (const v of VERSIONS) {
  const [ws, we] = WIN[v].map((d) => Date.parse(d + "T00:00:00Z"));
  const inW = dayRows.filter((r) => r.t >= ws && r.t <= we);
  const tot = inW.reduce((s, r) => s + r.exp, 0);
  const byV = {};
  for (const x of inW) byV[x.iver] = (byV[x.iver] || 0) + x.exp;
  winShares[v] = { tot, share: Object.fromEntries(Object.entries(byV).map(([k, e]) => [k, tot > 0 ? e / tot : null])) };
}

/* ---------------- Sheet 1: 主输出 ---------------- */
const s1 = workbook.worksheets.add("版本周日均转换率");
s1.showGridLines = false;
s1.tabColor = DARK;

s1.getRange("A2").values = [["AI工坊 App 各版本 周日均转换率（2026-07-13 ~ 2026-09-14）"]];
s1.getRange("A2").format.font = { name: CN, size: 14, bold: false, color: "#1F1F1F" };
s1.getRange("A3:J3").format.borders = { bottom: { style: "thin", color: "#8EA9DB" } };
s1.getRange("A4").values = [[
  "日均转换率 = 该版本该周内逐日「当日支付人数 ÷ 当日曝光人数」的算术平均，曝光人数为 0 的天不计入。空白 = 该周该版本无曝光（未上线或该版本当日曝光为 0）。",
]];
s1.getRange("A4").format.font = { name: CN, size: 9, italic: true, color: "#595959" };

const head1 = ["周", ...VERSIONS, "全版本合计"];
s1.getRange("A6:J6").values = [head1];
const s1rows = weeks.map((w, wi) => [
  w.label,
  ...VERSIONS.map((v) => (cells[wi][v] ? cells[wi][v].avgDailyRate : null)),
  weekTotals[wi].rate,
]);
s1.getRangeByIndexes(6, 0, s1rows.length, head1.length).values = s1rows;

s1.getRange("A6:J6").format = {
  fill: DARK,
  font: { name: CN, size: 10, bold: true, color: "#FFFFFF" },
  borders: { insideVertical: { style: "thin", color: "#FFFFFF" } },
  verticalAlignment: "center",
};
s1.getRange("A6:J6").format.horizontalAlignment = "center";
s1.getRange("A7:A16").format.font = { name: CN, size: 10 };
s1.getRange("B7:J16").format.font = { name: EN, size: 10 };
s1.getRange("B7:J16").format.numberFormat = "0.0000%";
s1.getRange("J7:J16").format.font = { name: EN, size: 10, bold: true };
s1.getRange("J7:J16").format.numberFormat = "0.0000%";
s1.getRange("A6:J16").format.borders = { preset: "all", style: "thin", color: THIN };
s1.getRange("B7:I16").conditionalFormats.add("colorScale", {
  colors: ["#FFFFFF", "#FFF2CC", "#F8CBAD"],
  thresholds: ["min", { type: "percentile", value: 50 }, "max"],
});
s1.getRange("A6:J16").format.autofitColumns();
s1.getRange("A6:A16").format.columnWidth = 16;
s1.getRange("B6:J6").format.columnWidth = 11;
s1.getRange("B7:J16").format.horizontalAlignment = "right";

/* ---------------- Sheet 2: 版本窗口曝光占比 ---------------- */
const s1b = workbook.worksheets.add("版本窗口曝光占比");
s1b.showGridLines = false;
s1b.tabColor = DARK;

s1b.getRange("A2").values = [["各版本更新窗口内的曝光占比（2026-07-13 ~ 2026-09-14）"]];
s1b.getRange("A2").format.font = { name: CN, size: 14, color: "#1F1F1F" };
s1b.getRange("A3:K3").format.borders = { bottom: { style: "thin", color: "#8EA9DB" } };
s1b.getRange("A4").values = [[
  "行 = 版本更新窗口（业务确认口径），列 = 版本。单元格 = 该版本在行窗口内的曝光人数 ÷ 该窗口 8 个版本曝光人数合计。曝光人数为 AI工坊 当日去重曝光用户数。",
]];
s1b.getRange("A4").format.font = { name: CN, size: 9, italic: true, color: "#595959" };

const head2b = ["版本更新窗口", "窗口日期", "窗口曝光人数合计", ...VERSIONS, "窗口天数"];
s1b.getRange("A6:L6").values = [head2b];
const rows2b = VERSIONS.map((v) => {
  const [ws, we] = WIN[v];
  const days = (Date.parse(we + "T00:00:00Z") - Date.parse(ws + "T00:00:00Z")) / DAY + 1;
  return [
    v,
    `${ws.slice(5)} ~ ${we.slice(5)}`,
    winShares[v].tot,
    ...VERSIONS.map((x) => (winShares[v].share[x] ? winShares[v].share[x] : null)),
    days,
  ];
});
s1b.getRangeByIndexes(6, 0, rows2b.length, head2b.length).values = rows2b;
s1b.getRange("A6:L6").format = {
  fill: DARK,
  font: { name: CN, size: 10, bold: true, color: "#FFFFFF" },
  borders: { insideVertical: { style: "thin", color: "#FFFFFF" } },
  horizontalAlignment: "center",
  verticalAlignment: "center",
};
s1b.getRange("A7:B14").format.font = { name: CN, size: 10 };
s1b.getRange("D7:K14").format.font = { name: EN, size: 10 };
s1b.getRange("C7:C14").format.font = { name: EN, size: 10 };
s1b.getRange("L7:L14").format.font = { name: EN, size: 10 };
s1b.getRange("C7:C14").format.numberFormat = "#,##0";
s1b.getRange("D7:K14").format.numberFormat = "0.0%";
s1b.getRange("A6:L14").format.borders = { preset: "all", style: "thin", color: THIN };
s1b.getRange("D7:K14").conditionalFormats.add("colorScale", {
  colors: ["#FFFFFF", "#FFF2CC", "#F8CBAD"],
  thresholds: ["min", { type: "percentile", value: 50 }, "max"],
});
s1b.getRange("A6:L14").format.autofitColumns();
s1b.getRange("A6:A14").format.columnWidth = 14;
s1b.getRange("B6:B14").format.columnWidth = 15;
s1b.getRange("C6:C14").format.columnWidth = 17;
s1b.getRange("D6:K14").format.columnWidth = 11;
s1b.getRange("D7:K14").format.horizontalAlignment = "right";

/* ---------------- Sheet 3: 版本周明细 ---------------- */
const s2 = workbook.worksheets.add("版本周明细");
s2.showGridLines = false;
const head2 = [
  "周", "起始日", "结束日", "版本", "有效天数", "周曝光人数", "周支付人数",
  "日均曝光人数", "日均支付人数", "日均转换率", "累计转换率", "版本曝光占比",
];
s2.getRangeByIndexes(0, 0, 1, head2.length).values = [head2];
const det = [];
for (let wi = 0; wi < weeks.length; wi += 1) {
  const w = weeks[wi];
  for (const v of VERSIONS) {
    const c = cells[wi][v];
    if (!c) continue;
    det.push([
      w.label,
      new Date(w.start),
      new Date(w.end),
      v,
      c.days,
      c.sumExp,
      c.sumPay,
      c.sumExp / c.days,
      c.sumPay / c.days,
      c.avgDailyRate,
      c.cumRate,
      c.share,
    ]);
  }
}
s2.getRangeByIndexes(1, 0, det.length, head2.length).values = det;
const last2 = det.length + 1;
s2.getRangeByIndexes(0, 0, 1, head2.length).format = {
  fill: HEAD_FILL,
  font: { name: CN, size: 10, bold: true },
  borders: { preset: "all", style: "thin", color: THIN },
};
s2.getRangeByIndexes(0, 0, 1, head2.length).format.horizontalAlignment = "center";
s2.getRangeByIndexes(1, 0, det.length, head2.length).format.borders = { preset: "all", style: "thin", color: THIN };
s2.getRangeByIndexes(1, 0, det.length, head2.length).format.font = { name: CN, size: 10 };
s2.getRange(`A2:A${last2}`).format.font = { name: CN, size: 10 };
s2.getRange(`D2:D${last2}`).format.font = { name: EN, size: 10 };
s2.getRange(`B2:C${last2}`).format.numberFormat = "yyyy-mm-dd";
s2.getRange(`B2:C${last2}`).format.font = { name: EN, size: 10 };
s2.getRange(`E2:J${last2}`).format.font = { name: EN, size: 10 };
s2.getRange(`E2:E${last2}`).format.numberFormat = "#,##0";
s2.getRange(`F2:G${last2}`).format.numberFormat = "#,##0";
s2.getRange(`H2:I${last2}`).format.numberFormat = "#,##0.0";
s2.getRange(`J2:K${last2}`).format.numberFormat = "0.0000%";
s2.getRange(`L2:L${last2}`).format.numberFormat = "0.0%";
s2.getRangeByIndexes(0, 0, det.length + 1, head2.length).format.autofitColumns();
s2.getRange(`A1:L${last2}`).format.columnWidth = 12;
s2.freezePanes.freezeRows(1);

/* ---------------- Sheet 3: 口径说明 ---------------- */
const s3 = workbook.worksheets.add("口径说明");
s3.showGridLines = false;
s3.getRange("A1").values = [["口径说明"]];
s3.getRange("A1").format.font = { name: CN, size: 14, bold: false };
s3.getRange("A2:B2").values = [["项目", "说明"]];
const notes = [
  ["样本范围", "AI工坊 App 端，8 个白名单版本：13.3.82 / 13.4.0 / 13.4.2 / 13.4.22 / 13.4.40 / 13.4.41 / 13.4.52 / 13.4.63。"],
  ["时间范围", "2026-07-13 ~ 2026-09-14（共 64 天，为源数据的实际可取日期）。"],
  ["周划分", "自然周，自 07-13 起每 7 天一周，共 10 行：07-13 / 07-20 / 07-27 / 08-03 / 08-10 / 08-17 / 08-24 / 08-31 / 09-07 / 09-14；末周仅 1 天（09-14）。"],
  ["版本更新窗口", "业务确认的 8 段窗口，连续且不重叠，合计覆盖 07-13 ~ 09-14：13.3.82 07-13~07-19；13.4.0 07-20~07-26；13.4.2 07-27~08-06；13.4.22 08-07~08-10；13.4.40 08-11~08-20；13.4.41 08-21~08-30；13.4.52 08-31~09-07；13.4.63 09-08~09-14。"],
  ["关于「7月13日 / 7月27日 / 8月10日 / 8月24日 / 9月7日」", "那 5 行是「周」不是「点」：每行代表从该日起 7 天的窗口（07-13~07-19、07-27~08-02、08-10~08-16、08-24~08-30、09-07~09-13），且只取了单周（隔周），漏掉了 07-20 / 08-03 / 08-17 / 08-31 四周。本表已补全为连续 10 周。"],
  ["曝光人数", "当日该版本在 AI工坊 的去重曝光用户数（用户天粒度）。"],
  ["支付人数", "当日该版本送出过 AI 礼物的去重用户数（用户天粒度）。"],
  ["日均转换率", "该版本该周内逐日「当日支付人数 ÷ 当日曝光人数」的算术平均；曝光人数为 0 的天不计入，也不按 0 参与平均。"],
  ["累计转换率", "该版本该周「支付人数合计 ÷ 曝光人数合计」，为占比口径，量级受曝光多少影响，仅作参考，不与日均转换率混用。"],
  ["版本曝光占比", "该版本该周曝光人数 ÷ 该周 8 个版本曝光人数合计，分母为 8 版本合计，不含白名单外的其他 App 版本。"],
  ["全版本合计", "该周 8 个版本合计的「支付人数合计 ÷ 曝光人数合计」。注意：用周内曝光占比对累计转换率加权求和，结果恒等于该值。"],
  ["空白含义", "该周该版本无曝光。多数情况是该版本尚未发布，也可能是已发布但当日曝光为 0。"],
  ["已知局限", "各版本长期共存、并非分段放量，版本效应与时间效应共线；单日单版支付人数常为 0~3 人，日均转换率波动大，读趋势比读单点更稳。"],
  ["源数据", "AI工坊_版本天明细_20260713-20260914.csv（Presto 取数，版本 × 天）。"],
];
s3.getRangeByIndexes(2, 0, notes.length, 2).values = notes;
s3.getRange("A2:B2").format = { fill: HEAD_FILL, font: { name: CN, size: 10, bold: true } };
s3.getRangeByIndexes(2, 0, notes.length, 2).format.font = { name: CN, size: 10 };
s3.getRangeByIndexes(2, 0, notes.length, 2).format.verticalAlignment = "top";
s3.getRangeByIndexes(2, 1, notes.length, 1).format.wrapText = true;
s3.getRange("A2:B2").format.columnWidth = 18;
s3.getRange("B2:B14").format.columnWidth = 105;

/* ---------------- Sheet 4: 源数据 ---------------- */
const s4 = workbook.worksheets.add("源数据_版本天");
s4.showGridLines = false;
const head4 = ["dt", "iver", "曝光人数", "支付人数", "AI礼物流水"];
const src4 = recs
  .slice()
  .sort((a, b) => (a.dt < b.dt ? -1 : a.dt > b.dt ? 1 : a.iver < b.iver ? -1 : 1))
  .map((r) => [r.dt, r.iver, r.exp, r.pay, r.amt]);
s4.getRangeByIndexes(0, 0, 1, head4.length).values = [head4];
s4.getRangeByIndexes(1, 0, src4.length, head4.length).values = src4;
s4.getRangeByIndexes(0, 0, 1, head4.length).format = {
  fill: HEAD_FILL,
  font: { name: CN, size: 10, bold: true },
};
s4.getRangeByIndexes(1, 0, src4.length, head4.length).format.font = { name: EN, size: 10 };
s4.getRange(`C2:D${src4.length + 1}`).format.numberFormat = "#,##0";
s4.getRange(`E2:E${src4.length + 1}`).format.numberFormat = "#,##0.0";
s4.getRangeByIndexes(0, 0, src4.length + 1, head4.length).format.autofitColumns();
s4.freezePanes.freezeRows(1);

workbook.recalculate();
await fs.mkdir("C:/Users/tiany/Desktop/AI工坊专题", { recursive: true });
const out = await SpreadsheetFile.exportXlsx(workbook);
await out.save(OUT);
console.log("saved", OUT);
console.log("weeks", weeks.length, "detail rows", det.length, "source rows", src4.length);
for (let wi = 0; wi < weeks.length; wi += 1) {
  const parts = VERSIONS.filter((v) => cells[wi][v]).map(
    (v) => `${v}=${(cells[wi][v].avgDailyRate * 100).toFixed(4)}%`,
  );
  console.log(weeks[wi].label, "| all=", (weekTotals[wi].rate * 100).toFixed(4) + "%", "|", parts.join(" "));
}
