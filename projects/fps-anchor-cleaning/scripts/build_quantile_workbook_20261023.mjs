import fs from "node:fs/promises";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const dataPath = "C:/Users/tiany/Desktop/FPS主播清洗_20261023/outputs/FPS头部腰部主播_开播时长分位数_月均10天门槛_20261023.json";
const outputDir = "C:/Users/tiany/Desktop/FPS主播清洗_20261023/outputs/01a1624c-a30a-7fb2-920d-19d253f20db4";
const outputPath = `${outputDir}/FPS头部腰部主播_开播时长增长测算_P50P75_20261023.xlsx`;

const payload = JSON.parse(await fs.readFile(dataPath, "utf8"));
const detailRows = payload.head_waist_detail.filter((row) => Number(row.is_main_category) === 1);
const excludedSmallSampleCnt = payload.head_waist_detail.length - detailRows.length;
const workbook = Workbook.create();

const COLORS = {
  navy: "#1F4E78",
  blue: "#2F75B5",
  green: "#548235",
  gray: "#7F7F7F",
  lightBlue: "#D9EAF7",
  lightGreen: "#E2F0D9",
  lightAmber: "#FFF2CC",
  lightRed: "#FCE4D6",
  lightGray: "#F2F2F2",
  border: "#D9E1F2",
  white: "#FFFFFF",
  text: "#262626",
  muted: "#666666",
};

function matrixFromRows(rows, defs) {
  return rows.map((row) => defs.map(([, key]) => row[key] ?? null));
}

function styleTitle(sheet, endCol, title, note) {
  sheet.showGridLines = false;
  sheet.getRange("A2").values = [[title]];
  sheet.getRange(`A2:${endCol}2`).format = {
    font: { name: "KaiTi", size: 14, bold: true, color: COLORS.text },
    verticalAlignment: "center",
  };
  sheet.getRange(`A2:${endCol}2`).format.rowHeight = 24;
  sheet.getRange("A3").values = [[note]];
  sheet.getRange(`A3:${endCol}3`).format = {
    font: { name: "KaiTi", size: 9, italic: true, color: COLORS.muted },
    verticalAlignment: "center",
    wrapText: false,
  };
  sheet.getRange(`A3:${endCol}3`).format.rowHeight = 18;
  sheet.getRange(`A4:${endCol}4`).format.fill = COLORS.navy;
  sheet.getRange(`A4:${endCol}4`).format.rowHeight = 3;
}

function styleHeader(sheet, rowNumber, colCount) {
  const endCol = String.fromCharCode(64 + colCount);
  const range = sheet.getRange(`A${rowNumber}:${endCol}${rowNumber}`);
  range.format = {
    fill: COLORS.navy,
    font: { name: "KaiTi", size: 10, bold: true, color: COLORS.white },
    horizontalAlignment: "center",
    verticalAlignment: "center",
    wrapText: true,
    borders: { preset: "all", style: "thin", color: COLORS.white },
  };
  range.format.rowHeight = 32;
}

function applyTextAndNumbers(sheet, startRow, endRow, textColumns, numberColumns, numberFormats = {}) {
  for (const col of textColumns) {
    const range = sheet.getRange(`${col}${startRow}:${col}${endRow}`);
    range.format.font = { name: "Calibri", size: 10, color: COLORS.text };
    range.format.horizontalAlignment = "left";
    range.format.numberFormat = "@";
  }
  for (const col of numberColumns) {
    const range = sheet.getRange(`${col}${startRow}:${col}${endRow}`);
    range.format.font = { name: "Calibri", size: 10, color: COLORS.text };
    range.format.horizontalAlignment = "right";
    if (numberFormats[col]) range.format.numberFormat = numberFormats[col];
  }
}

function setWidths(sheet, widths) {
  for (const [col, width] of Object.entries(widths)) {
    sheet.getRange(`${col}1:${col}1`).format.columnWidth = width;
  }
}

function addQuantileSheet() {
  const sheet = workbook.worksheets.add("分位数汇总");
  sheet.tabColor = COLORS.navy;
  const defs = [
    ["主品类", "main_game_name"],
    ["主播层级", "acu_type"],
    ["主播数", "anchor_cnt"],
    ["指标", "metric"],
    ["P25", "p25"],
    ["P50", "p50"],
    ["P75", "p75"],
    ["组内最小值", "min"],
    ["组内最大值", "max"],
  ];
  const headers = defs.map(([label]) => label);
  const body = matrixFromRows(payload.quantiles, defs);
  const endCol = "I";
  styleTitle(
    sheet,
    endCol,
    "主要品类头部与腰部主播日均开播时长分位数",
    `指标：年日均开播时长（分钟）｜月均开播天数≥10天｜主要品类按头部与腰部合计至少5人定义`,
  );
  sheet.getRange(`A5:${endCol}5`).values = [headers];
  sheet.getRange(`A6:${endCol}${5 + body.length}`).values = body;
  styleHeader(sheet, 5, defs.length);
  const table = sheet.tables.add(`A5:${endCol}${5 + body.length}`, true, "QuantileSummaryTable");
  table.style = "TableStyleMedium2";
  table.showBandedColumns = false;
  table.showBandedRows = true;
  sheet.freezePanes.freezeRows(5);
  setWidths(sheet, { A: 20, B: 12, C: 10, D: 34, E: 15, F: 15, G: 15, H: 15, I: 15 });
  applyTextAndNumbers(sheet, 6, 5 + body.length, ["A", "B", "D"], ["C", "E", "F", "G", "H", "I"], {
    C: "#,##0",
    E: "#,##0.00",
    F: "#,##0.00",
    G: "#,##0.00",
    H: "#,##0.00",
    I: "#,##0.00",
  });
  sheet.getRange(`A6:I${5 + body.length}`).format.verticalAlignment = "center";
  sheet.getRange(`A6:I${5 + body.length}`).format.rowHeight = 21;
  return sheet;
}

function addBelowCountSheet() {
  const sheet = workbook.worksheets.add("低于分位人数");
  sheet.tabColor = COLORS.blue;
  const defs = [
    ["主品类", "main_game_name"],
    ["主播层级", "acu_type"],
    ["主播数", "anchor_cnt"],
    ["指标", "metric"],
    ["低于P25人数", "below_p25_cnt"],
    ["低于P50人数", "below_p50_cnt"],
    ["低于P75人数", "below_p75_cnt"],
  ];
  const headers = defs.map(([label]) => label);
  const body = matrixFromRows(payload.below_counts, defs);
  const endCol = "G";
  styleTitle(
    sheet,
    endCol,
    "各主品类层级低于日均开播时长分位数的主播人数",
    "指标：年日均开播时长（分钟）｜月均开播天数≥10天｜“低于”按严格小于对应分位数计算",
  );
  sheet.getRange(`A5:${endCol}5`).values = [headers];
  sheet.getRange(`A6:${endCol}${5 + body.length}`).values = body;
  styleHeader(sheet, 5, defs.length);
  const table = sheet.tables.add(`A5:${endCol}${5 + body.length}`, true, "BelowQuantileCountTable");
  table.style = "TableStyleMedium2";
  table.showBandedColumns = false;
  sheet.freezePanes.freezeRows(5);
  setWidths(sheet, { A: 20, B: 12, C: 10, D: 34, E: 15, F: 15, G: 15 });
  applyTextAndNumbers(sheet, 6, 5 + body.length, ["A", "B", "D"], ["C", "E", "F", "G"], {
    C: "#,##0",
    E: "#,##0",
    F: "#,##0",
    G: "#,##0",
  });
  sheet.getRange(`A6:G${5 + body.length}`).format.verticalAlignment = "center";
  sheet.getRange(`A6:G${5 + body.length}`).format.rowHeight = 21;
  return sheet;
}

function addGrowthDetailSheet({ sheetName, tabColor, tableName, percentileName, quantileColumn }) {
  const sheet = workbook.worksheets.add(sheetName);
  sheet.tabColor = tabColor;
  const defs = [
    ["主播ID", "luid"],
    ["主播昵称", "snick"],
    ["主品类ID", "main_game_id"],
    ["主品类", "main_game_name"],
    ["2026年日均ACU", "avg_daily_acu_2026"],
    ["年日均开播时长（分钟）", "avg_daily_live_minutes"],
    ["ACU层级", "acu_type"],
    ["年度开播天数", "total_live_day_cnt"],
    ["有效月份数", "active_month_cnt"],
    ["月均开播天数（10个月）", "avg_monthly_live_days_10months"],
    ["有开播月份月均天数", "avg_monthly_live_days_active_months"],
    ["年度开播小时", "total_live_hours_2026"],
    ["分位分析范围", "is_main_category"],
    ["品类层级样本数", "category_tier_anchor_cnt"],
    ["开播时长分位标签", "开播时长分位标签"],
    ["目标增长直播时长（分钟）", "target_growth_live_minutes"],
    ["增长成功率", "growth_success_rate"],
    ["平均ACU增幅（成功事件平均值）", "avg_acu_growth_rate"],
    ["增长ACU", "growth_acu"],
    ["新增观时（人·分钟）", "added_watch_minutes"],
  ];
  const headers = defs.map(([label]) => label);
  const body = matrixFromRows(detailRows, defs).map((row) => {
    const copy = [...row];
    copy[0] = String(row[0]);
    copy[12] = row[12] === 1 ? "纳入分位数" : "小样本参考";
    return copy;
  });
  const endCol = "T";
  styleTitle(
    sheet,
    endCol,
    `${percentileName}目标下的头部与腰部主播明细`,
    `共 ${detailRows.length} 人｜已剔除小样本品类 ${excludedSmallSampleCnt} 人｜目标值按“主品类 x ACU层级”的年日均开播时长${percentileName}计算`,
  );
  sheet.getRange(`A5:${endCol}5`).values = [headers];
  sheet.getRange(`A6:${endCol}${5 + body.length}`).values = body;
  const firstDataRow = 6;
  const lastDataRow = 5 + body.length;
  sheet.getRange(`P${firstDataRow}:T${firstDataRow}`).formulas = [[
    `=MAX(0,SUMIFS('分位数汇总'!$${quantileColumn}$6:$${quantileColumn}$15,'分位数汇总'!$A$6:$A$15,D${firstDataRow},'分位数汇总'!$B$6:$B$15,G${firstDataRow})-F${firstDataRow})`,
    `=IF(G${firstDataRow}="头部主播",0.375,IF(G${firstDataRow}="腰部主播",0.4286,0))`,
    `=IF(G${firstDataRow}="头部主播",0.5128,IF(G${firstDataRow}="腰部主播",4.3944,0))`,
    `=E${firstDataRow}*Q${firstDataRow}*R${firstDataRow}`,
    `=S${firstDataRow}*P${firstDataRow}`,
  ]];
  sheet.getRange(`P${firstDataRow}:T${lastDataRow}`).fillDown();
  styleHeader(sheet, 5, defs.length);
  const table = sheet.tables.add(`A5:${endCol}${5 + body.length}`, true, tableName);
  table.style = "TableStyleMedium2";
  table.showBandedColumns = false;
  sheet.freezePanes.freezeRows(5);
  sheet.freezePanes.freezeColumns(2);
  setWidths(sheet, {
    A: 22, B: 24, C: 12, D: 19, E: 17, F: 22, G: 12, H: 14,
    I: 13, J: 20, K: 20, L: 18, M: 16, N: 16, O: 20,
    P: 24, Q: 14, R: 28, S: 16, T: 22,
  });
  applyTextAndNumbers(sheet, 6, 5 + body.length, ["A", "B", "C", "D", "G", "M", "O"], ["E", "F", "H", "I", "J", "K", "L", "N", "P", "Q", "R", "S", "T"], {
    E: "#,##0.00",
    F: "#,##0.00",
    H: "#,##0",
    I: "#,##0",
    J: "#,##0.00",
    K: "#,##0.00",
    L: "#,##0.00",
    N: "#,##0",
    P: "#,##0.00",
    Q: "0.00%",
    R: "0.00%",
    S: "#,##0.00",
    T: "#,##0.00",
  });
  // ID 按文本写入；预览器对长数字串使用 0 格式展示完整值，Excel 中仍保持文本类型。
  sheet.getRange(`A6:A${5 + body.length}`).format.numberFormat = "0";
  sheet.getRange(`A6:O${5 + body.length}`).format.verticalAlignment = "center";
  sheet.getRange(`A6:O${5 + body.length}`).format.rowHeight = 21;
  sheet.getRange(`P6:T${5 + body.length}`).format = {
    fill: COLORS.lightGreen,
    verticalAlignment: "center",
  };
  sheet.getRange(`P6:T${5 + body.length}`).format.rowHeight = 21;
  sheet.getRange(`O6:O${5 + body.length}`).conditionalFormats.add("containsText", {
    text: "低于25分位数", format: { fill: COLORS.lightRed, font: { color: "#C00000", bold: true } },
  });
  sheet.getRange(`O6:O${5 + body.length}`).conditionalFormats.add("containsText", {
    text: "75分位数及以上", format: { fill: COLORS.lightGreen },
  });

  const summaryStart = lastDataRow + 2;
  sheet.getRange(`A${summaryStart}:B${summaryStart + 4}`).values = [
    ["目标增长直播时长合计（分钟）", null],
    ["增长ACU合计", null],
    ["新增观时合计（人·分钟）", null],
    ["新增观时占 91,858,247", null],
    ["折算比例", null],
  ];
  sheet.getRange(`B${summaryStart}`).formulas = [[`=SUM(P${firstDataRow}:P${lastDataRow})`]];
  sheet.getRange(`B${summaryStart + 1}`).formulas = [[`=SUM(S${firstDataRow}:S${lastDataRow})`]];
  sheet.getRange(`B${summaryStart + 2}`).formulas = [[`=SUM(T${firstDataRow}:T${lastDataRow})`]];
  sheet.getRange(`B${summaryStart + 3}`).formulas = [[`=B${summaryStart + 2}/91858247`]];
  sheet.getRange(`B${summaryStart + 4}`).formulas = [[`=91858247/B${summaryStart + 2}`]];
  sheet.getRange(`A${summaryStart}:B${summaryStart + 4}`).format = {
    fill: COLORS.lightBlue,
    font: { name: "KaiTi", size: 10, bold: true, color: COLORS.text },
    verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: COLORS.border },
  };
  sheet.getRange(`B${summaryStart}:B${summaryStart + 4}`).format = {
    font: { name: "Calibri", size: 10, bold: true, color: COLORS.text },
    horizontalAlignment: "right",
    verticalAlignment: "center",
    numberFormat: "#,##0.00",
  };
  sheet.getRange(`B${summaryStart + 3}`).format.numberFormat = "0.00%";
  sheet.getRange(`B${summaryStart + 4}`).format.numberFormat = '"约 1 / "0.0';
  sheet.getRange(`A${summaryStart}:B${summaryStart + 4}`).format.rowHeight = 22;
  return sheet;
}

function addNotesSheet() {
  const sheet = workbook.worksheets.add("口径说明");
  sheet.tabColor = COLORS.gray;
  const body = payload.notes.map((row) => [...row]);
  const smallSampleNoteIndex = body.findIndex(([label]) => label === "小样本处理");
  if (smallSampleNoteIndex >= 0) {
    body[smallSampleNoteIndex] = [
      "小样本品类剔除",
      `主要品类按头部与腰部合计至少5人定义；本次明细已剔除其余小样本品类 ${excludedSmallSampleCnt} 人`,
    ];
  }
  body.push(
    ["P75目标增长直播时长", "max(0, 所属主品类与ACU层级P75 - 当前年日均开播时长)，单位为分钟"],
    ["P50目标增长直播时长", "max(0, 所属主品类与ACU层级P50 - 当前年日均开播时长)，单位为分钟"],
    ["增长成功率", "头部主播37.50%，腰部主播42.86%；按主播层级统一取值"],
    ["平均ACU增幅", "成功后事件平均值：头部主播51.28%，腰部主播439.44%"],
    ["增长ACU", "当前年日均ACU × 增长成功率 × 平均ACU增幅"],
    ["新增观时", "增长ACU × 目标增长直播时长，单位为人·分钟"],
  );
  styleTitle(
    sheet,
    "B",
    "口径与交付说明",
    "来源：FPS正常主播年日均开播时长与月均开播天数明细｜月均开播天数≥10天｜截至 2026-10-20",
  );
  sheet.getRange(`A5:B${4 + body.length}`).values = body;
  styleHeader(sheet, 5, 2);
  setWidths(sheet, { A: 22, B: 105 });
  sheet.getRange(`A6:A${4 + body.length}`).format.font = { name: "KaiTi", size: 10, bold: true, color: COLORS.text };
  sheet.getRange(`B6:B${4 + body.length}`).format.font = { name: "KaiTi", size: 10, color: COLORS.text };
  sheet.getRange(`A6:B${4 + body.length}`).format.verticalAlignment = "top";
  sheet.getRange(`A6:B${4 + body.length}`).format.wrapText = true;
  sheet.getRange(`A6:B${4 + body.length}`).format.rowHeight = 28;
  sheet.getRange(`A5:B${4 + body.length}`).format.borders = { preset: "all", style: "thin", color: COLORS.border };
  return sheet;
}

const quantileSheet = addQuantileSheet();
const belowCountSheet = addBelowCountSheet();
const p75GrowthSheet = addGrowthDetailSheet({
  sheetName: "头部腰部明细",
  tabColor: COLORS.green,
  tableName: "HeadWaistDetailTable",
  percentileName: "P75",
  quantileColumn: "G",
});
const p50GrowthSheet = addGrowthDetailSheet({
  sheetName: "P50增长测算",
  tabColor: COLORS.blue,
  tableName: "P50GrowthDetailTable",
  percentileName: "P50",
  quantileColumn: "F",
});
const notesSheet = addNotesSheet();

workbook.recalculate();
await fs.mkdir(outputDir, { recursive: true });

for (const [sheet, range, fileName] of [
  [quantileSheet, "A1:I20", "quantiles_duration_activity10.png"],
  [belowCountSheet, "A1:G20", "below_counts_duration_activity10.png"],
  [p75GrowthSheet, "A1:T30", "head_waist_growth_top.png"],
  [p75GrowthSheet, "A70:T80", "head_waist_growth_bottom.png"],
  [p50GrowthSheet, "A1:T30", "head_waist_p50_growth_top.png"],
  [p50GrowthSheet, "A70:T80", "head_waist_p50_growth_bottom.png"],
  [notesSheet, "A1:B29", "notes_duration_activity10.png"],
]) {
  const preview = await workbook.render({ sheetName: sheet.name, range, scale: 1, format: "png" });
  await fs.writeFile(`${outputDir}/${fileName}`, new Uint8Array(await preview.arrayBuffer()));
}

const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);

const sheets = await workbook.inspect({ kind: "sheet", include: "id,name" });
const errorScan = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!",
  options: { useRegex: true, maxResults: 100 },
  summary: "final formula error scan",
});

console.log(sheets.ndjson);
console.log(errorScan.ndjson);
console.log(outputPath);
