import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const projectDir = "C:\\Users\\tiany\\Desktop\\FPS主播清洗_20261023";
const outputDir = path.join(projectDir, "outputs");
const previewDir = path.join(projectDir, "previews");
const outputPath = path.join(outputDir, "FPS主播年日均开播时长清洗_20261023.xlsx");

const files = {
  kept: path.join(outputDir, "fps_anchor_kept_20261023.csv"),
  excluded: path.join(outputDir, "fps_anchor_excluded_20261023.csv"),
  summary: path.join(outputDir, "fps_anchor_rule_summary_20261023.csv"),
  rules: path.join(outputDir, "fps_anchor_rule_hits_20261023.csv"),
  clubAudit: path.join(outputDir, "fps_anchor_club_audit_20261023.csv"),
  dataQuality: path.join(outputDir, "fps_anchor_data_quality_20261023.csv"),
  clubRules: path.join(outputDir, "fps_anchor_club_rules_20261023.csv"),
  eventRules: path.join(outputDir, "fps_anchor_event_rules_20261023.csv"),
  buildSummary: path.join(outputDir, "fps_anchor_build_summary_20261023.json"),
};

const colors = {
  title: "#16202A",
  muted: "#5B6770",
  header: "#1F4E5F",
  headerText: "#FFFFFF",
  band: "#EAF2F5",
  border: "#C9D6DB",
  warning: "#FFF2CC",
  danger: "#FCE8E6",
  success: "#E2F0D9",
  outputTab: "#1F4E5F",
  auditTab: "#6B7C85",
};

function parseCsv(text) {
  const source = text.replace(/^\uFEFF/, "");
  const rows = [];
  let row = [];
  let value = "";
  let quoted = false;
  for (let i = 0; i < source.length; i += 1) {
    const ch = source[i];
    if (quoted) {
      if (ch === '"') {
        if (source[i + 1] === '"') {
          value += '"';
          i += 1;
        } else {
          quoted = false;
        }
      } else {
        value += ch;
      }
    } else if (ch === '"') {
      quoted = true;
    } else if (ch === ",") {
      row.push(value);
      value = "";
    } else if (ch === "\n") {
      row.push(value);
      rows.push(row);
      row = [];
      value = "";
    } else if (ch !== "\r") {
      value += ch;
    }
  }
  if (value.length || row.length) {
    row.push(value);
    rows.push(row);
  }
  const headers = rows.shift() ?? [];
  return rows
    .filter((values) => values.some((entry) => entry !== ""))
    .map((values) => Object.fromEntries(headers.map((header, index) => [header, values[index] ?? ""])));
}

async function readCsv(filePath) {
  return parseCsv(await fs.readFile(filePath, "utf8"));
}

function applySheetBase(sheet, tabColor = colors.auditTab) {
  sheet.showGridLines = false;
  sheet.tabColor = tabColor;
}

function setTitle(sheet, title, note) {
  sheet.getRange("A1").values = [[title]];
  sheet.getRange("A1").format.font = { name: "KaiTi", size: 14, bold: true, color: colors.title };
  sheet.getRange("A2").values = [[note]];
  sheet.getRange("A2").format.font = { name: "KaiTi", size: 9, italic: true, color: colors.muted };
  sheet.getRange("A1:Z1").format.borders = { bottom: { style: "thin", color: colors.border } };
}

function writeTable(sheet, startRow, headers, data, options = {}) {
  const headerRow = startRow;
  const firstDataRow = startRow + 1;
  const endRow = firstDataRow + data.length - 1;
  sheet.getRangeByIndexes(headerRow - 1, 0, 1, headers.length).values = [headers];
  if (data.length) {
    sheet.getRangeByIndexes(firstDataRow - 1, 0, data.length, headers.length).values = data;
  }
  const headerRange = sheet.getRangeByIndexes(headerRow - 1, 0, 1, headers.length);
  headerRange.format = {
    fill: options.headerFill ?? colors.header,
    font: { name: "Calibri", size: 10, bold: true, color: colors.headerText },
    verticalAlignment: "center",
    wrapText: true,
    borders: { preset: "all", style: "thin", color: colors.headerText },
  };
  headerRange.format.rowHeight = 30;
  if (data.length) {
    const body = sheet.getRangeByIndexes(firstDataRow - 1, 0, data.length, headers.length);
    body.format.font = { name: "KaiTi", size: 9, color: colors.title };
    body.format.verticalAlignment = "center";
    body.format.borders = { preset: "outside", style: "thin", color: colors.border };
  }
  return { firstDataRow, endRow };
}

function applyColumnWidths(sheet, widths) {
  widths.forEach((width, index) => {
    sheet.getRangeByIndexes(0, index, 1, 1).format.columnWidth = width;
  });
}

function coerceDetailRows(rows, headers) {
  const integerFields = new Set([
    "source_line",
    "is_event_anchor",
    "is_club_anchor",
    "is_placeholder_nickname",
    "is_data_quality_error",
    "is_low_activity",
    "is_high_outlier",
    "is_kept",
  ]);
  const numberFields = new Set(["avg_daily_live_minutes", "avg_daily_live_hours"]);
  return rows.map((row) => headers.map((header) => {
    const value = row[header] ?? "";
    if (integerFields.has(header)) return value === "" ? "" : Number(value);
    if (numberFields.has(header)) return value === "" ? "" : Number(value);
    return value;
  }));
}

async function addDetailSheet(workbook, name, title, note, rows, tabColor) {
  const sheet = workbook.worksheets.add(name);
  applySheetBase(sheet, tabColor);
  setTitle(sheet, title, note);
  const headers = Object.keys(rows[0] ?? {});
  const data = coerceDetailRows(rows, headers);
  const range = writeTable(sheet, 4, headers, data);
  sheet.freezePanes.freezeRows(4);
  sheet.freezePanes.freezeColumns(2);
  const widths = headers.map((header) => {
    if (header === "luid") return 18;
    if (header === "snick") return 24;
    if (header.includes("event_hit_term")) return 28;
    if (header.includes("club_name")) return 24;
    if (header.includes("club_hit_term")) return 18;
    if (header.includes("exclusion_reason")) return 30;
    if (header.includes("placeholder_hit_term")) return 22;
    if (header === "source_line") return 12;
    if (header === "avg_daily_live_minutes") return 20;
    if (header === "avg_daily_live_hours") return 20;
    if (header.startsWith("is_")) return 15;
    return 18;
  });
  applyColumnWidths(sheet, widths);
  if (headers.includes("avg_daily_live_minutes") && data.length) {
    const durationColumn = headers.indexOf("avg_daily_live_minutes");
    sheet.getRangeByIndexes(4, durationColumn, data.length, 1).format.numberFormat = "#,##0.000000";
    sheet.getRangeByIndexes(4, durationColumn, data.length, 1).format.font = { name: "Calibri", size: 9, color: colors.title };
  }
  if (headers.includes("avg_daily_live_hours") && data.length) {
    const hoursColumn = headers.indexOf("avg_daily_live_hours");
    sheet.getRangeByIndexes(4, hoursColumn, data.length, 1).format.numberFormat = "0.0000";
    sheet.getRangeByIndexes(4, hoursColumn, data.length, 1).format.font = { name: "Calibri", size: 9, color: colors.title };
  }
  return { sheet, headers, ...range };
}

const workbook = Workbook.create();
const buildSummary = JSON.parse(await fs.readFile(files.buildSummary, "utf8"));
const summaryRows = await readCsv(files.summary);
const ruleRows = await readCsv(files.rules);
const clubAuditRows = await readCsv(files.clubAudit);
const dataQualityRows = await readCsv(files.dataQuality);
const clubRuleRows = await readCsv(files.clubRules);
const eventRuleRows = await readCsv(files.eventRules);
const keptRows = await readCsv(files.kept);
const excludedRows = await readCsv(files.excluded);

const overview = workbook.worksheets.add("清洗汇总");
applySheetBase(overview, colors.outputTab);
setTitle(
  overview,
  "FPS主播年日均开播时长清洗汇总",
  "时间口径以原始CSV为准；低开播门槛为30分钟/日，高值阈值仅使用Q3+3×IQR且不设负下限。未做ACU分层。原始luid含科学计数法，最终行数不能直接视为唯一主播数；source_line可用于行级追溯。",
);
overview.getRange("A2:C2").merge();
overview.getRange("A2:C2").format.wrapText = true;
overview.getRange("A2:C2").format.rowHeight = 34;

const summaryMetrics = [
  ["原始数据行数", buildSummary.rows, "行"],
  ["最终保留明细行数", buildSummary.kept, "行"],
  ["最终剔除明细行数", buildSummary.excluded, "行"],
  ["数据质量异常", buildSummary.raw_rule_counts["数据质量异常"], "行"],
  ["赛事/内容账号", buildSummary.raw_rule_counts["赛事/内容账号"], "规则原始命中，最终按顺序剔除"],
  ["俱乐部电竞主播", buildSummary.raw_rule_counts["俱乐部电竞主播"], "规则原始命中"],
  ["低开播主播", buildSummary.raw_rule_counts["低开播主播（<30分钟/日）"], "原始规则命中：<30分钟/日"],
  ["高异常主播", buildSummary.raw_rule_counts["高异常主播（>高值阈值）"], "在赛事、俱乐部、低开播剔除后计算"],
  ["IQR统计样本", buildSummary.thresholds.iqr_base_rows, "行"],
  ["Q1", buildSummary.thresholds.q1, "分钟/日"],
  ["Q3", buildSummary.thresholds.q3, "分钟/日"],
  ["IQR", buildSummary.thresholds.iqr, "分钟/日"],
  ["高值阈值", buildSummary.thresholds.high_threshold_minutes, `${buildSummary.thresholds.high_threshold_hours.toFixed(2)} 小时/日`],
];
writeTable(overview, 4, ["指标", "数值", "单位/说明"], summaryMetrics);
applyColumnWidths(overview, [24, 22, 48]);
overview.getRange("B5:B17").format.font = { name: "Calibri", size: 10, color: colors.title };
overview.getRange("B5:B13").format.numberFormat = "#,##0";
overview.getRange("B14:B17").format.numberFormat = "#,##0.0000";
overview.getRange("B8:B9").format.fill = colors.warning;
overview.getRange("B10:B11").format.fill = colors.warning;
overview.getRange("B17").format.fill = colors.danger;
overview.freezePanes.freezeRows(3);

await addDetailSheet(
  workbook,
  "保留样本",
  "最终保留明细前200行预览",
  `完整保留明细共${keptRows.length}行，见fps_anchor_kept_20261023.csv。本页仅展示前200行，便于查看字段结构。`,
  keptRows.slice(0, 200),
  colors.outputTab,
);

await addDetailSheet(
  workbook,
  "剔除样本",
  "被剔除明细前200行预览",
  `完整剔除明细共${excludedRows.length}行，见fps_anchor_excluded_20261023.csv。final_exclusion_reason为首个剔除原因，all_exclusion_reasons保留全部命中。`,
  excludedRows.slice(0, 200),
  colors.auditTab,
);

const fileList = workbook.worksheets.add("文件清单");
applySheetBase(fileList, colors.outputTab);
setTitle(fileList, "清洗结果文件清单", "完整明细使用CSV交付，避免在Excel中加载数万行后影响筛选和打开速度。CSV均为UTF-8 BOM编码。");
writeTable(fileList, 4, ["文件", "内容", "数据行数", "格式"], [
  ["fps_anchor_kept_20261023.csv", "最终保留的完整行级明细", String(keptRows.length), "CSV / UTF-8 BOM"],
  ["fps_anchor_excluded_20261023.csv", "被剔除的完整行级明细", String(excludedRows.length), "CSV / UTF-8 BOM"],
  ["fps_anchor_rule_hits_20261023.csv", "各剔除规则命中人数", String(ruleRows.length), "CSV / UTF-8 BOM"],
  ["fps_anchor_club_audit_20261023.csv", "全部俱乐部命中记录", String(clubAuditRows.length), "CSV / UTF-8 BOM"],
  ["fps_anchor_data_quality_20261023.csv", "原始数据质量异常记录", String(dataQualityRows.length), "CSV / UTF-8 BOM"],
  ["FPS主播年日均开播时长清洗_20261023.xlsx", "汇总、规则、俱乐部审计与样本预览", "-", "Excel"],
]);
applyColumnWidths(fileList, [46, 42, 16, 22]);
fileList.freezePanes.freezeRows(4);

const rulesSheet = workbook.worksheets.add("规则对账");
applySheetBase(rulesSheet, colors.outputTab);
setTitle(rulesSheet, "各剔除规则命中人数", "sequential_removed_count为按业务执行顺序的实际剔除人数；raw_flag_hit_count为规则独立命中人数，可能跨规则重叠。");
const ruleCsvHeaders = ["rule_name", "raw_flag_hit_count", "before_rule_count", "sequential_removed_count", "removal_rate_before_rule", "rule_note"];
const ruleHeaders = ["规则", "规则独立命中人数", "执行前样本数", "顺序实际剔除人数", "执行前剔除率", "说明"];
const ruleData = ruleRows.map((row) => ruleCsvHeaders.map((header) => {
  if (header === "removal_rate_before_rule") return Number(row[header]);
  if (["raw_flag_hit_count", "before_rule_count", "sequential_removed_count"].includes(header)) return Number(row[header]);
  return row[header];
}));
writeTable(rulesSheet, 4, ruleHeaders, ruleData);
applyColumnWidths(rulesSheet, [28, 18, 18, 22, 20, 72]);
rulesSheet.getRange("B5:D10").format.numberFormat = "#,##0";
rulesSheet.getRange("E5:E10").format.numberFormat = "0.00%";
rulesSheet.freezePanes.freezeRows(4);

const clubSheet = workbook.worksheets.add("俱乐部审计");
applySheetBase(clubSheet, colors.auditTab);
setTitle(clubSheet, "俱乐部缩写命中抽样复核", "短代码仅按大写前缀/独立词边界匹配；AG按All Gamers常用前缀；WE、IG、TE要求代码后紧跟中文或分隔符；17和TT要求代码后是分隔符。");
const clubHeaders = ["luid", "snick", "main_game_id", "main_game_name", "avg_daily_live_minutes", "source_line", "club_name", "club_hit_term", "club_match_mode", "short_code_requires_review", "review_result"];
const clubData = clubAuditRows.map((row) => clubHeaders.map((header) => {
  if (header === "source_line" || header === "short_code_requires_review") return Number(row[header]);
  if (header === "avg_daily_live_minutes") return Number(row[header]);
  return row[header];
}));
writeTable(clubSheet, 4, clubHeaders, clubData);
applyColumnWidths(clubSheet, [18, 24, 13, 18, 20, 12, 24, 18, 36, 20, 40]);
clubSheet.freezePanes.freezeRows(4);
clubSheet.freezePanes.freezeColumns(2);
if (clubData.length) {
  clubSheet.getRangeByIndexes(4, 4, clubData.length, 1).format.numberFormat = "#,##0.000000";
  clubSheet.getRangeByIndexes(4, 9, clubData.length, 1).conditionalFormats.add("cellIs", {
    operator: "equal",
    formula: 1,
    format: { fill: colors.warning },
  });
}

const guide = workbook.worksheets.add("规则说明");
applySheetBase(guide, colors.auditTab);
setTitle(guide, "清洗口径与俱乐部核对来源", "规则先按昵称识别赛事/内容账号和占位昵称，再识别俱乐部电竞主播；低开播剔除后，在剩余样本上按Q3+3×IQR计算高值阈值。");
guide.getRange("A4:D8").values = [
  ["口径项", "定义", "边界", "说明"],
  ["赛事/内容账号", "昵称包含赛事、联赛、官方、活动、解说、二路、回放、集锦、电竞等词", "命中任一即剔除", "赛事与内容词按包含匹配，英文忽略大小写"],
  ["占位昵称", "空白昵称或“我是一颗小虎牙”", "包含匹配", "空白昵称另在数据质量页保留行级记录"],
  ["俱乐部主播", "命中已核对俱乐部全称、中文名、长代码或收紧后的短代码", "短代码非任意子串", "避免EDG、TE、17等误伤"],
  ["高值异常", "Q3 + 3×IQR", "仅在赛事、俱乐部、低开播剔除后计算", "不设负下限；等于阈值不剔除"],
];
guide.getRange("A4:D4").format = { fill: colors.header, font: { name: "Calibri", size: 10, bold: true, color: colors.headerText } };
guide.getRange("A4:D8").format.borders = { preset: "all", style: "thin", color: colors.border };
guide.getRange("A5:D8").format.font = { name: "KaiTi", size: 9, color: colors.title };
guide.getRange("A5:D8").format.wrapText = true;
guide.getRange("A10:D13").values = [
  ["核对来源", "用途", "链接", "核对内容"],
  ["无畏契约赛事官网", "VCT CN现行队伍代码", "https://vct.qq.com/", "FPX、RA、DRG、NOVA、TEC、KBG、WOL、AQ等"],
  ["英雄联盟赛事官网", "常见LPL俱乐部代码与中文简称", "https://lpl.qq.com/", "EDG、BLG、IG、JDG、LGD、LNG、NIP、OMG、TES、TT、WBG、WE等"],
  ["VLR.gg中国区战队排名", "英文全称与常用代码对照", "https://www.vlr.gg/rankings/china", "All Gamers、EDward Gaming、Bilibili Gaming、Wolves Esports等"],
];
guide.getRange("A10:D10").format = { fill: colors.header, font: { name: "Calibri", size: 10, bold: true, color: colors.headerText } };
guide.getRange("A10:D13").format.borders = { preset: "all", style: "thin", color: colors.border };
guide.getRange("A11:D13").format.font = { name: "KaiTi", size: 9, color: colors.title };
guide.getRange("A11:D13").format.wrapText = true;
guide.getRange("A15:D15").values = [["俱乐部名称", "别名/代码", "匹配方式", "来源类型"]];
const clubRuleMatrix = clubRuleRows.map((row) => [row.club_name, row.alias, row.match_mode, row.source_type]);
guide.getRangeByIndexes(15, 0, clubRuleMatrix.length, 4).values = clubRuleMatrix;
const mappingHeader = guide.getRange("A15:D15");
mappingHeader.format = { fill: colors.header, font: { name: "Calibri", size: 10, bold: true, color: colors.headerText } };
const mappingBody = guide.getRangeByIndexes(15, 0, clubRuleMatrix.length, 4);
mappingBody.format.font = { name: "KaiTi", size: 9, color: colors.title };
mappingBody.format.borders = { preset: "outside", style: "thin", color: colors.border };
const eventStart = 18 + clubRuleMatrix.length;
guide.getRangeByIndexes(eventStart - 1, 0, 1, 3).values = [["赛事/占位词", "类型", "匹配方式"]];
const eventMatrix = eventRuleRows.map((row) => [row.term, row.rule_type, row.match_mode]);
guide.getRangeByIndexes(eventStart, 0, eventMatrix.length, 3).values = eventMatrix;
guide.getRangeByIndexes(eventStart - 1, 0, 1, 3).format = { fill: colors.header, font: { name: "Calibri", size: 10, bold: true, color: colors.headerText } };
guide.getRangeByIndexes(eventStart, 0, eventMatrix.length, 3).format.font = { name: "KaiTi", size: 9, color: colors.title };
applyColumnWidths(guide, [30, 32, 58, 58]);
guide.freezePanes.freezeRows(2);

const quality = workbook.worksheets.add("数据质量");
applySheetBase(quality, colors.auditTab);
setTitle(quality, "原始CSV数据质量异常记录", "异常记录单独保留，不进入阈值计算、统计样本和最终保留明细；source_line对应原始CSV物理行号。空白昵称在Excel显示为（空白昵称），CSV保留原始空格。");
const qualityHeaders = ["luid", "snick", "main_game_id", "main_game_name", "avg_daily_live_minutes", "source_line", "data_quality_note", "handling"];
const qualityData = dataQualityRows.map((row) => qualityHeaders.map((header) => {
  if (header === "source_line") return Number(row[header]);
  if (header === "avg_daily_live_minutes") return row[header] === "" ? "" : Number(row[header]);
  if (header === "snick" && row[header].trim() === "") return "（空白昵称）";
  return row[header];
}));
writeTable(quality, 4, qualityHeaders, qualityData);
applyColumnWidths(quality, [18, 22, 13, 18, 20, 12, 44, 54]);
quality.getRange("A9:H9").merge();
quality.getRange("A9").values = [["luid格式提示：原始CSV将大量luid以科学计数法保存，存在不可逆精度损失；请以source_line定位原始行，并在重跑取数时强制导出完整字符串luid后再做人物级去重。"]];
quality.getRange("A9:H9").format = {
  fill: colors.warning,
  font: { name: "KaiTi", size: 9, bold: true, color: colors.title },
  wrapText: true,
  verticalAlignment: "center",
};
quality.getRange("A9:H9").format.rowHeight = 34;
quality.freezePanes.freezeRows(4);

workbook.recalculate();

const overviewCheck = await workbook.inspect({
  kind: "table",
  range: "清洗汇总!A1:C17",
  include: "values,formulas",
  tableMaxRows: 20,
  tableMaxCols: 6,
  maxChars: 8000,
});
console.log("OVERVIEW_CHECK");
console.log(overviewCheck.ndjson);

const formulaErrors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!",
  options: { useRegex: true, maxResults: 100 },
  summary: "final formula error scan",
});
console.log("FORMULA_ERRORS");
console.log(formulaErrors.ndjson);

await fs.mkdir(previewDir, { recursive: true });
const previewSheets = [
  ["清洗汇总", "A1:C17"],
  ["保留样本", "A1:F24"],
  ["剔除样本", "A1:F24"],
  ["规则对账", "A1:F10"],
  ["俱乐部审计", "A1:K24"],
  ["规则说明", "A1:D28"],
  ["数据质量", "A1:H12"],
  ["文件清单", "A1:D10"],
];
for (const [sheetName, range] of previewSheets) {
  const preview = await workbook.render({ sheetName, range, scale: 1, format: "png" });
  await fs.writeFile(
    path.join(previewDir, `${sheetName}.png`),
    new Uint8Array(await preview.arrayBuffer()),
  );
}

await fs.mkdir(outputDir, { recursive: true });
const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);

const imported = await SpreadsheetFile.importXlsx(await FileBlob.load(outputPath));
const sheetCheck = await imported.inspect({ kind: "sheet", include: "id,name" });
console.log("SHEETS");
console.log(sheetCheck.ndjson);
console.log(JSON.stringify({
  outputPath,
  fileSizeBytes: (await fs.stat(outputPath)).size,
  keptRows: keptRows.length,
  excludedRows: excludedRows.length,
  clubAuditRows: clubAuditRows.length,
  dataQualityRows: dataQualityRows.length,
}));
