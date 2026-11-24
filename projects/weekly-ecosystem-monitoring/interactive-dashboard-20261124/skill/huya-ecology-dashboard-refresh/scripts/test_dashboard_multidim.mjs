import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const port = 9334;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const list = await fetch(`http://127.0.0.1:${port}/json/list`).then(r => r.json());
const target = list.find(item => item.type === "page" && item.url.startsWith("file:///"));
if (!target) throw new Error("No dashboard page target found");

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  ws.addEventListener("open", resolve, { once: true });
  ws.addEventListener("error", reject, { once: true });
});

let nextId = 1;
const pending = new Map();
const exceptions = [];
ws.addEventListener("message", event => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) {
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(JSON.stringify(message.error)));
    else resolve(message.result);
  }
  if (message.method === "Runtime.exceptionThrown") {
    const details = message.params.exceptionDetails || {};
    exceptions.push({
      text: details.text || "runtime exception",
      description: details.exception?.description || "",
      line: details.lineNumber,
      column: details.columnNumber,
    });
  }
});

function send(method, params = {}) {
  const id = nextId++;
  ws.send(JSON.stringify({ id, method, params }));
  return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
}

async function evaluate(expression) {
  const result = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
  if (result.exceptionDetails) {
    throw new Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text || "evaluation failed");
  }
  return result.result.value;
}

async function screenshot(name) {
  const shot = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: true });
  fs.writeFileSync(`C:/Users/Huya/Documents/Codex/2026-11-24/qin/work/${name}.png`, Buffer.from(shot.data, "base64"));
}

async function change(selector, value, eventName = "change") {
  await evaluate(`(() => { const el=document.querySelector(${JSON.stringify(selector)}); el.value=${JSON.stringify(value)}; el.dispatchEvent(new Event(${JSON.stringify(eventName)},{bubbles:true})); })()`);
  await delay(450);
}

async function click(selector) {
  await evaluate(`document.querySelector(${JSON.stringify(selector)})?.click()`);
  await delay(350);
}

await send("Runtime.enable");
await send("Page.enable");
if (process.argv[2]) {
  await send("Page.navigate", { url: pathToFileURL(path.resolve(process.argv[2])).href });
  await delay(1500);
}
await send("Page.reload", { ignoreCache: true });
await delay(5500);
exceptions.length = 0;

const initial = await evaluate(`(() => ({
  title: document.querySelector("h1")?.textContent,
  primaryKpi: document.querySelector(".kpi-main")?.textContent.trim(),
  kpis: [...document.querySelectorAll(".kpi-label")].map(x => x.textContent.trim()),
  chips: [...document.querySelectorAll(".dimension-chip .chip-text")].map(x => x.textContent.trim()),
  rows: [...document.querySelectorAll("#singleTableBody tr")].slice(0,20).map(row => ({kind:row.dataset.nodeKind,name:row.querySelector(".node-name")?.textContent})),
  headers:[...document.querySelectorAll("#singleTableBody")].length?[...document.querySelectorAll("#singleTableBody").item(0).closest("table").querySelectorAll("thead th")].map(x=>x.textContent.trim()):[],
  contributions:[...document.querySelectorAll("#singleTableBody tr")].slice(0,3).map(row=>({parent:row.children[5]?.textContent.trim(),total:row.children[6]?.textContent.trim()})),
  compareModes:[...document.querySelectorAll("[data-compare-mode]")].map(x=>x.dataset.compareMode),
  multiVisible:Boolean(document.querySelector("#treeTableBody")),
  multiToggle:Boolean(document.querySelector("[data-toggle-multi]")),
  chartSvg: document.querySelectorAll(".chart svg").length,
  chartTypes:[...document.querySelectorAll("[data-chart-type]")].map(x=>x.dataset.chartType),
  activeChartType:window.__dashDebug.state.chartType,
  visualizationCanvas:Boolean(document.querySelector('[data-visualization-canvas="true"]')),
  eventDisabled: document.getElementById("eventFilter")?.disabled,
  scope: document.querySelector(".scope-strip")?.textContent.replace(/\\s+/g," ").trim(),
  trend: window.__dashDebug.trendSeries("dau").slice(-3),
}))()`);
await screenshot("multidim_v2_initial");

const primaryDau = Number((initial.primaryKpi || "").replace(/\D/g, ""));
const trendLast = initial.trend.at(-1)?.value || 0;
const trendPrev = initial.trend.at(-2)?.value || 1;

await click('[data-toggle-multi]');
const multiOpened = await evaluate(`(() => ({visible:Boolean(document.querySelector("#treeTableBody")),rows:document.querySelectorAll("#treeTableBody tr").length}))()`);
await click('#treeTableBody [data-tree-toggle]');
const treeExpanded = await evaluate(`(() => ({rows:document.querySelectorAll("#treeTableBody tr").length,expanded:document.querySelectorAll("#treeTableBody [aria-expanded='true']").length}))()`);

await click('[data-dim-remove="group"]');
const afterRemove = await evaluate(`(() => ({
  chips:[...document.querySelectorAll(".dimension-chip .chip-text")].map(x=>x.textContent.trim()),
  rows:[...document.querySelectorAll("#singleTableBody tr")].slice(0,5).map(row=>({kind:row.dataset.nodeKind,name:row.querySelector(".node-name")?.textContent})),
  title:[...document.querySelectorAll(".section-title")].map(x=>x.textContent.trim()).find(x=>x.includes("Top20"))
}))()`);

await evaluate(`(() => { const s=document.getElementById("dimensionAddSelect"); s.value="group"; })()`);
await click("#addDimensionButton");
const afterAdd = await evaluate(`(() => ({
  stack:[...window.__dashDebug.state.dimStack],
  chips:[...document.querySelectorAll(".dimension-chip .chip-text")].map(x=>x.textContent.trim())
}))()`);
await click('[data-dim-remove="group"]');
await click('[data-dim-remove="tier"]');
await click('[data-dim-remove="guild"]');
const reduced = await evaluate(`(() => ({
  stack:[...window.__dashDebug.state.dimStack],
  chips:[...document.querySelectorAll(".dimension-chip .chip-text")].map(x=>x.textContent.trim())
}))()`);

await evaluate(`(() => { const s=document.getElementById("dimensionAddSelect"); s.value="guild"; })()`);
await click("#addDimensionButton");
await click('[data-dim="guild"][data-dim-shift="-1"]');
await click('[data-dim="guild"][data-dim-shift="-1"]');
const reordered = await evaluate(`(() => ({
  stack:[...window.__dashDebug.state.dimStack],
  chips:[...document.querySelectorAll(".dimension-chip .chip-text")].map(x=>x.textContent.trim()),
  firstKind:document.querySelector("#singleTableBody tr")?.dataset.nodeKind
}))()`);

await click('#singleTableBody tr[data-node-kind="guild"]');
const guildLevel = await evaluate(`(() => ({
  path:[...window.__dashDebug.state.path],
  breadcrumb:document.querySelector(".breadcrumb")?.textContent.replace(/\\s+/g," ").trim(),
  nextKind:document.querySelector("#singleTableBody tr")?.dataset.nodeKind,
  title:[...document.querySelectorAll(".section-title")].find(x=>x.textContent.includes("Top20"))?.textContent.trim()
}))()`);

await click('#singleTableBody tr[data-node-kind="category"]');
const categoryLevel = await evaluate(`(() => ({
  path:[...window.__dashDebug.state.path],
  breadcrumb:document.querySelector(".breadcrumb")?.textContent.replace(/\\s+/g," ").trim(),
  nextKind:document.querySelector("#singleTableBody tr")?.dataset.nodeKind,
  title:[...document.querySelectorAll(".section-title")].find(x=>x.textContent.includes("Top20"))?.textContent.trim()
}))()`);

await click('#singleTableBody tr[data-node-kind="anchor"]');
const anchorLevel = await evaluate(`(() => ({
  path:[...window.__dashDebug.state.path],
  breadcrumb:document.querySelector(".breadcrumb")?.textContent.replace(/\\s+/g," ").trim(),
  rows:document.querySelectorAll("#singleTableBody tr").length,
  title:[...document.querySelectorAll(".section-title")].find(x=>x.textContent.includes("Top20"))?.textContent.trim()
}))()`);
await click("[data-clear-anchor]");

await evaluate(`(() => {
  const source=document.querySelector('[data-dimension-chip="anchor"]');
  const target=document.querySelector('[data-dimension-chip="guild"]');
  const dataTransfer=new DataTransfer();
  source.dispatchEvent(new DragEvent("dragstart",{bubbles:true,dataTransfer}));
  target.dispatchEvent(new DragEvent("dragover",{bubbles:true,dataTransfer}));
  target.dispatchEvent(new DragEvent("drop",{bubbles:true,dataTransfer}));
})()`);
await delay(450);
const dragged = await evaluate(`(() => ({
  stack:[...window.__dashDebug.state.dimStack],
  path:[...window.__dashDebug.state.path],
  chips:[...document.querySelectorAll(".dimension-chip .chip-text")].map(x=>x.textContent.trim())
}))()`);

await click('[data-crumb-index="-1"]');
await click('[data-compare-mode="month"]');
const monthControls = await evaluate(`(() => ({current:document.querySelector("#monthCurrent")?.value||"",previous:document.querySelector("#monthPrevious")?.value||""}))()`);
await change("#monthCurrent", "2026-10");
await change("#monthPrevious", "2026-09");
const monthApplied = await evaluate(`(() => ({
  period:window.__dashDebug.activePeriod(),
  mode:window.__dashDebug.state.compareMode,
  stack:[...window.__dashDebug.state.dimStack],
  comparisonAvailable:window.__dashDebug.buildRanking().comparisonAvailable,
  coverageNotice:document.querySelector(".coverage-notice")?.textContent.replace(/\s+/g," ").trim()||"",
  tableText:document.querySelector("#singleTableBody")?.textContent.replace(/\s+/g," ").trim()||"",
  rows:window.__dashDebug.buildRanking().rows.slice(0,3).map(r=>({name:r.name,current:r.current,previous:r.previous,delta:r.delta,days:r.agg?.days}))
}))()`);
await screenshot("multidim_v2_month");
await click('[data-compare-mode="custom"]');
const customVisible = await evaluate(`Boolean(document.getElementById("customPeriodPanel"))`);
await change("#customPreviousStart", "2026-11-09", "input");
await change("#customPreviousEnd", "2026-11-11", "input");
await change("#customCurrentStart", "2026-11-16", "input");
await change("#customCurrentEnd", "2026-11-18", "input");
await click("#applyCustomPeriod");
const customApplied = await evaluate(`(() => ({
  period:window.__dashDebug.activePeriod(),
  scope:document.querySelector(".scope-strip")?.textContent.replace(/\\s+/g," ").trim(),
  trend:window.__dashDebug.trendSeries("dau"),
  error:document.querySelector(".custom-message.error")?.textContent||""
}))()`);

async function searchAnchor(query) {
  await evaluate(`(() => { const el=document.getElementById("anchorSearch"); el.value=${JSON.stringify(query)}; el.dispatchEvent(new Event("input",{bubbles:true})); })()`);
  await delay(450);
  const results = await evaluate(`[...document.querySelectorAll("[data-pick-anchor]")].map(x=>x.textContent.trim())`);
  await click("[data-pick-anchor]");
  const state = await evaluate(`(() => ({
    title:document.querySelector(".focus-title")?.textContent||"",
    scope:document.querySelector(".scope-strip")?.textContent.replace(/\\s+/g," ").trim()||"",
    metrics:[...document.querySelectorAll(".focus-metric label")].map(x=>x.textContent.trim()),
    primary:document.querySelector(".kpi-main")?.textContent.trim()||document.querySelector(".focus-metric strong")?.textContent.trim()||"",
    trendDau:window.__dashDebug.trendSeries("dau"),
    trendAttr:window.__dashDebug.trendSeries("attr"),
    dimensionVisible:Boolean(document.querySelector("#dimensionStack")),
    multiVisible:Boolean(document.querySelector("#treeTableBody")),
    anchorMode:Boolean(document.querySelector(".anchor-mode")),
    coverageNotice:Boolean(document.querySelector(".coverage-notice"))
  }))()`);
  return { results, ...state };
}

const searchByUid = await searchAnchor("333393123");
await screenshot("multidim_v2_anchor_mode");
const searchByNickname = await searchAnchor("DANK1NG");
const searchByRoomId = await searchAnchor("10188");
const searchByFuzzySubsequence = await searchAnchor("dankng");
const searchByNormalizedTokens = await searchAnchor("dank 1ng");
await click("[data-clear-anchor]");
await send("Page.reload", { ignoreCache: true });
await delay(5500);

await change("#metric", "interactionRate");
const interaction = await evaluate(`(() => ({
  chartTitles:[...document.querySelectorAll(".chart-title")].map(x=>x.textContent.trim()),
  rowCount:document.querySelectorAll("#singleTableBody tr").length,
  rateValues:[...document.querySelectorAll("#singleTableBody tr")].slice(0,10).map(row=>row.children[7]?.textContent.trim()),
  ranking:window.__dashDebug.ranking().slice(0,3).map(r=>({name:r.name,rate:r.interactionAgg?.interactionRate,users:r.interactionAgg?.intUser}))
}))()`);

async function drillInteraction(kind) {
  await click(`#singleTableBody tr[data-node-kind="${kind}"]`);
  await delay(500);
  return evaluate(`(() => ({
    path:[...window.__dashDebug.state.path],
    rowCount:document.querySelectorAll("#singleTableBody tr").length,
    rates:[...document.querySelectorAll("#singleTableBody tr")].slice(0,10).map(row=>row.children[7]?.textContent.trim()),
    empty:Boolean(document.querySelector("#singleTableBody .empty"))
  }))()`);
}

const interactionGroup = await drillInteraction("group");
const interactionCategory = await drillInteraction("category");
const interactionGuild = await drillInteraction("guild");
const interactionTier = await drillInteraction("tier");
const interactionAnchor = await drillInteraction("anchor");

const granularities = await evaluate(`(() => {
  const select=document.getElementById("granularity"),out=[];
  for(const value of ["day","week","month","quarter","year"]) {
    select.value=value; select.dispatchEvent(new Event("change",{bubbles:true}));
    out.push({value,titles:[...document.querySelectorAll(".chart-title")].map(x=>x.textContent.trim()),charts:document.querySelectorAll(".chart svg").length,points:window.__dashDebug.trendSeries("interactionRate").length});
  }
  return out;
})()`);
await delay(500);
await screenshot("multidim_v2_custom");

const checks = {
  rendered: initial.title === "全品类生态监控看板" && initial.chartSvg === 2 && initial.rows.length === 4,
  freeVisualizationCanvas: initial.visualizationCanvas && initial.chartTypes.join("|") === "line|bar|stack" && initial.activeChartType === "line",
  contributionColumns: initial.headers.includes("父层贡献*") && initial.headers.includes("总盘贡献*") && initial.contributions.every(x=>x.parent&&x.parent!=="-"&&x.total&&x.total!=="-"),
  singleAndTreeViews: initial.multiVisible === false && initial.multiToggle && multiOpened.visible && multiOpened.rows >= 3 && treeExpanded.rows > multiOpened.rows && treeExpanded.expanded >= 1,
  platformDauScale: primaryDau >= 4_500_000 && primaryDau <= 5_800_000,
  trendLastBucketDailyAverage: trendLast >= 3_500_000 && trendLast / trendPrev >= 0.65,
  defaultFiveDimensions: initial.chips.join("|") === "内容大类|品类|公会|主播层级|主播",
  removeDimension: afterRemove.chips.join("|") === "品类|公会|主播层级|主播" && afterRemove.rows[0]?.kind === "category",
  addDimension: afterAdd.stack.join("|") === "category|guild|tier|anchor|group" && reduced.chips.join("|") === "品类|主播",
  reorderDimension: reordered.stack.join("|") === "guild|category|anchor" && reordered.firstKind === "guild",
  dragReorderDimension: dragged.stack.join("|") === "anchor|guild|category" && dragged.chips.join("|") === "主播|公会|品类",
  arbitraryGuildCategoryAnchor: guildLevel.nextKind === "category" && categoryLevel.nextKind === "anchor" && anchorLevel.rows === 1 && anchorLevel.breadcrumb.includes("公会") && anchorLevel.breadcrumb.includes("品类") && anchorLevel.breadcrumb.includes("主播"),
  comparisonModes: initial.compareModes.join("|") === "week|month|quarter|year|custom",
  monthComparison: monthControls.current === "2026-10" && monthControls.previous === "2026-09" && monthApplied.mode === "month" && monthApplied.period.currentDates[0] === "2026-10-01" && monthApplied.period.currentDates.at(-1) === "2026-10-31" && monthApplied.period.previousDates[0] === "2026-09-01" && monthApplied.period.previousDates.at(-1) === "2026-09-30",
  monthCoverageGuard: monthApplied.comparisonAvailable === false && monthApplied.rows.every(row => row.previous === null && row.delta === null) && monthApplied.tableText.includes("数据不足") && monthApplied.coverageNotice.includes("无覆盖"),
  customPeriodVisible: customVisible,
  customPeriodApplied: customApplied.period.currentDates.join("|") === "2026-11-16|2026-11-17|2026-11-18" && customApplied.period.previousDates.join("|") === "2026-11-09|2026-11-10|2026-11-11" && !customApplied.error,
  customTrendScoped: customApplied.trend.length === 2 && customApplied.trend.every(point => point.value >= 0),
  anchorSearchUid: searchByUid.results.some(x => x.includes("333393123")) && searchByUid.title === "DANK1NG" && primaryDau > 0,
  anchorModeSimplified: searchByUid.anchorMode && !searchByUid.dimensionVisible && !searchByUid.multiVisible,
  anchorDirectCoverageNoticeHidden: searchByUid.coverageNotice === false,
  anchorSearchNickname: searchByNickname.results.some(x => x.includes("DANK1NG")) && searchByNickname.title === "DANK1NG",
  anchorSearchRoomId: searchByRoomId.results.some(x => x.includes("10188")) && searchByRoomId.title === "DANK1NG",
  anchorSearchFuzzySubsequence: searchByFuzzySubsequence.results.some(x => x.includes("DANK1NG")) && searchByFuzzySubsequence.title === "DANK1NG",
  anchorSearchNormalizedTokens: searchByNormalizedTokens.results.some(x => x.includes("DANK1NG")) && searchByNormalizedTokens.title === "DANK1NG",
  anchorFocusMetrics: ["观看 DAU","归属 DAU","打赏流水","互动人数","互动率"].every(label => searchByUid.metrics.includes(label)),
  interactionRateRootRows: interaction.rowCount >= 3 && interaction.rateValues.some(x => x && x !== "-") && interaction.ranking.every(x => Number.isFinite(x.rate)),
  interactionRateAllLevels: [interactionGroup,interactionCategory,interactionGuild,interactionTier,interactionAnchor].every((level,index) => level.rowCount > 0 && !level.empty && level.rates.every(x => x && x !== "-") && level.path.length === index + 1),
  allGranularities: granularities.length === 5 && granularities.every(x => x.titles.length === 2 && x.charts === 2 && x.points > 0),
  eventStillDisabled: initial.eventDisabled === true,
  noRuntimeExceptions: exceptions.length === 0,
};

const comparisons = {
  afterAddStack: afterAdd.stack.join("|"),
  afterAddExpected: "category|guild|tier|anchor|group",
  reducedChips: reduced.chips.join("|"),
  reducedExpected: "品类|主播",
  reorderedStack: reordered.stack.join("|"),
  reorderedExpected: "guild|category|anchor",
  reorderedFirstKind: reordered.firstKind,
  draggedStack: dragged.stack.join("|"),
};

console.log(JSON.stringify({ checks, comparisons, primaryDau, initial, multiOpened, treeExpanded, afterRemove, afterAdd, reduced, reordered, dragged, guildLevel, categoryLevel, anchorLevel, monthControls, monthApplied, customVisible, customApplied, searchByUid, searchByNickname, searchByRoomId, searchByFuzzySubsequence, searchByNormalizedTokens, interaction, interactionGroup, interactionCategory, interactionGuild, interactionTier, interactionAnchor, granularities, exceptions }, null, 2));
ws.close();
process.exit(0);
