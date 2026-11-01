import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(scriptDir, "..");
const root = process.env.NON_DOUYIN_VALORANT_DIR ?? "C:/Users/tiany/Desktop/无畏契约份额增长/无畏契约主播潜力分析/非抖无畏主播挖掘";
const outputRoot = resolve(projectRoot, "artifacts");
const isTrue = (v) => v === true || v === 1 || String(v).trim().toLowerCase() === "true" || String(v).trim() === "1";
const csv = (rows) => rows.map((row) => row.map((v) => {
  const s = v == null ? "" : String(v);
  return /[",\r\n]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s;
}).join(",")).join("\n") + "\n";
const count = (xs, fn) => xs.reduce((m, x) => { const k = fn(x); m[k] = (m[k] ?? 0) + 1; return m; }, {});

const sourceWb = await SpreadsheetFile.importXlsx(await FileBlob.load(`${root}/非抖无畏主播挖掘.xlsx`));
const sourceRows = sourceWb.worksheets.getItemAt(0).getUsedRange().values;
const headers = sourceRows[0].map(String);
const idx = Object.fromEntries(headers.map((h, i) => [h, i]));
const sourceData = sourceRows.slice(1);
const sourcePlatforms = ["bilibili", "douyu", "kuaishou"];
const uidSet = new Set(sourceData.filter((r) => sourcePlatforms.includes(String(r[idx["平台"]]))).map((r) => String(r[idx["主播uid"]])));
const sepByUid = new Map();
for (const r of sourceData) {
  const rawDate = r[idx["日期"]];
  const d = rawDate instanceof Date ? rawDate : new Date(rawDate);
  const ym = Number.isNaN(d.getTime()) ? String(rawDate).slice(0, 7) : `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}`;
  if (ym !== "2026-09") continue;
  const acu = Number(r[idx["有效acu"]]);
  const tier = acu >= 2000 ? "头部" : acu >= 1000 ? "颈部" : acu >= 100 ? "腰部" : "尾部";
  sepByUid.set(String(r[idx["主播uid"]]), { platform: String(r[idx["平台"]]), tier });
}
const sourceSummary = Object.fromEntries(sourcePlatforms.map((p) => {
  const all = new Set(sourceData.filter((r) => r[idx["平台"]] === p).map((r) => String(r[idx["主播uid"]])));
  const sep = [...sepByUid.entries()].filter(([, v]) => v.platform === p);
  const tiers = count(sep, ([, v]) => v.tier);
  return [p, { total: all.size, withSep: sep.length, noSep: all.size - sep.length, head: tiers["头部"] ?? 0, neck: tiers["颈部"] ?? 0, waist: tiers["腰部"] ?? 0, tail: tiers["尾部"] ?? 0 }];
}));
const sepTierCounts = count([...sepByUid.values()], (v) => v.tier);
sourceSummary.all = {
  total: uidSet.size,
  withSep: sepByUid.size,
  noSep: uidSet.size - sepByUid.size,
  head: sepTierCounts["头部"] ?? 0,
  neck: sepTierCounts["颈部"] ?? 0,
  waist: sepTierCounts["腰部"] ?? 0,
  tail: sepTierCounts["尾部"] ?? 0
};

const finalWb = await SpreadsheetFile.importXlsx(await FileBlob.load(`${root}/非抖无畏主播_头部基准筛选_含战队与剔战队_20261014.xlsx`));
const selectedRows = finalWb.worksheets.getItem("最终名单").getRange("A3:P13").values;
const judgeRows = finalWb.worksheets.getItem("判定总表").getRange("A3:N36").values;
const teamWb = await SpreadsheetFile.importXlsx(await FileBlob.load(`${root}/非抖无畏主播_剔除战队_平台基准筛选_20261014.xlsx`));
const teamRows = teamWb.worksheets.getItem("候选主播_曾达头部").getRange("A2:Q27").values;
const selectionSummary = {};
for (const p of [...sourcePlatforms, "all"]) {
  const cand = p === "all" ? judgeRows : judgeRows.filter((r) => r[0] === p);
  const sel = p === "all" ? selectedRows : selectedRows.filter((r) => r[0] === p);
  const team = p === "all" ? teamRows : teamRows.filter((r) => r[0] === p);
  selectionSummary[p] = {
    candidates: cand.length,
    assessable: cand.filter((r) => Number(r[10]) > 0).length,
    selected: sel.length,
    selectedTeam: sel.filter((r) => r[1] === "战队").length,
    selectedNonTeam: sel.filter((r) => r[1] === "非战队").length,
    robust: sel.filter((r) => r[8] === "稳健").length,
    relaxed: sel.filter((r) => r[8] === "仅放宽").length,
    excludedCandidates: team.length,
    excludedAssessable: team.filter((r) => Number(r[3]) > 0).length,
    excludedR2Head: team.filter((r) => isTrue(r[12])).length,
    excludedR2OverallMedian: team.filter((r) => isTrue(r[16])).length
  };
}

const summaryZh = [["平台","曾达头部候选数","可评估候选数","最终入选数","最终入选_战队","最终入选_非战队","稳健入选","仅放宽入选","1至9月有数据主播数","9月无数据主播数","唯一主播总数","9月头部","9月颈部","9月腰部","9月尾部","剔除战队后候选数","剔除战队后可评估数","剔除战队_R2头部基准入选数","剔除战队_R2整体中位入选数"]];
const summaryEn = [["platform","ever_head_candidates","assessable_candidates","final_selected","selected_team","selected_non_team","selected_robust","selected_relaxed","streamers_with_jan_sep_data","streamers_without_sep_data","unique_streamers","sep_head","sep_neck","sep_waist","sep_tail","team_excluded_candidates","team_excluded_assessable","team_excluded_r2_head","team_excluded_r2_overall_median"]];
for (const p of [...sourcePlatforms, "all"]) {
  const s = selectionSummary[p], q = sourceSummary[p];
  summaryZh.push([p, s.candidates, s.assessable, s.selected, s.selectedTeam, s.selectedNonTeam, s.robust, s.relaxed, q.withSep, q.noSep, q.total, q.head, q.neck, q.waist, q.tail, s.excludedCandidates, s.excludedAssessable, s.excludedR2Head, s.excludedR2OverallMedian]);
  summaryEn.push([p, s.candidates, s.assessable, s.selected, s.selectedTeam, s.selectedNonTeam, s.robust, s.relaxed, q.withSep, q.noSep, q.total, q.head, q.neck, q.waist, q.tail, s.excludedCandidates, s.excludedAssessable, s.excludedR2Head, s.excludedR2OverallMedian]);
}

const benchRows = finalWb.worksheets.getItem("平台月度基准").getRange("A1:J24").values;
const benchZh = [["基准场景","平台","月份","环比中位"]];
const benchEn = [["benchmark_scenario","platform","month","median_mom_pct"]];
const scenarioMap = new Map([
  ["一、头部主播·环比中位（含战队）· 战队主播用", "head_with_team"],
  ["二、头部主播·环比中位（剔除战队）· bilibili非战队用", "head_without_team"],
  ["三、全体主播·环比中位（含战队）· 斗鱼/快手用", "all_with_team"],
  ["四、全体主播·环比中位（剔除战队）· 参考", "all_without_team"]
]);
for (let i = 0; i < benchRows.length; i++) {
  const scenario = scenarioMap.get(benchRows[i][0]);
  if (!scenario) continue;
  const monthHeader = benchRows[i+1];
  for (let j = i + 2; j < benchRows.length && sourcePlatforms.includes(benchRows[j][0]); j++) {
    for (let m = 1; m < monthHeader.length; m++) {
      const v = benchRows[j][m];
      if (v == null) continue;
      benchZh.push([scenario, benchRows[j][0], `2026-${String(Number(String(monthHeader[m]).replace("月", ""))).padStart(2,"0")}`, v]);
      benchEn.push([scenario, benchRows[j][0], `2026-${String(Number(String(monthHeader[m]).replace("月", ""))).padStart(2,"0")}`, v]);
    }
  }
}

const outputs = {
  "non-douyin-discovery-summary.csv": csv(summaryZh),
  "non-douyin-discovery-summary.en.csv": csv(summaryEn),
  "non-douyin-monthly-benchmarks.csv": csv(benchZh),
  "non-douyin-monthly-benchmarks.en.csv": csv(benchEn)
};
mkdirSync(outputRoot, { recursive: true });
for (const [name, body] of Object.entries(outputs)) writeFileSync(`${outputRoot}/${name}`, body, "utf8");
console.log(JSON.stringify({
  outputs,
  audit: { sourceSummary, selectionSummary, benchmarkRows: benchEn.length - 1 }
}, null, 2));
