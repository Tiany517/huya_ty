import path from "node:path";
import { pathToFileURL } from "node:url";

const port = 9334;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const list = await fetch(`http://127.0.0.1:${port}/json/list`).then(response => response.json());
const target = list.find(item => item.type === "page" && item.url.startsWith("file:///"));
if (!target) throw new Error("No browser page target found");

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
  if (message.method === "Runtime.exceptionThrown") exceptions.push(message.params.exceptionDetails);
});

function send(method, params = {}) {
  const id = nextId++;
  ws.send(JSON.stringify({ id, method, params }));
  return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
}

async function evaluate(expression) {
  const response = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
  if (response.exceptionDetails) throw new Error(response.exceptionDetails.exception?.description || response.exceptionDetails.text);
  return response.result.value;
}

await send("Runtime.enable");
await send("Page.enable");
await send("Page.navigate", {
  url: pathToFileURL(path.resolve(process.argv[2] || "C:/Users/Huya/Documents/Codex/2026-11-24/qin/work/daily_glass_test/daily_alert_report_test.html")).href,
});
for (let attempt = 0; attempt < 30; attempt += 1) {
  await delay(500);
  if (await evaluate("window.__visualizationReady === true")) break;
}
if (!(await evaluate("window.__visualizationReady === true"))) {
  const diagnostics = await evaluate(`(() => {
    let syntaxError="";try{new Function(document.scripts[1]?.textContent||"");}catch(error){syntaxError=error.stack||String(error);}
    return {
    url: location.href,
    readyState: document.readyState,
    scriptStarted: window.__visualizationScriptStarted === true,
    syntaxError,
    scriptCount: document.scripts.length,
    dataBytes: document.getElementById("visualization-data-gzip")?.textContent.length || 0,
    chartText: document.getElementById("visualizationChart")?.textContent.trim(),
    bodyText: document.body?.innerText.slice(0, 300)
  };})()`);
  console.log(JSON.stringify({ status: "failed", reason: "visualization not ready", diagnostics, exceptions }, null, 2));
  ws.close();
  process.exit(1);
}

const initial = await evaluate(`(() => ({
  ready: window.__visualizationReady === true,
  scope: window.__visualizationDebug?.state.scope,
  dimension: window.__visualizationDebug?.state.dimension,
  granularity: window.__visualizationDebug?.state.granularity,
  chartType: window.__visualizationDebug?.state.chartType,
  rows: window.__visualizationDebug?.dataLength || 0,
  anchorRows: window.__visualizationDebug?.anchorDataLength || 0,
  scopeOptions: document.querySelectorAll("#visualizationScope option").length,
  scopeLabels: [...document.querySelectorAll("#visualizationScope option")].map(x => x.textContent.trim()),
  dimensionOptions: [...document.querySelectorAll("#visualizationDimension option")].map(x => x.value),
  dimensionDisabled: document.getElementById("visualizationDimension")?.disabled,
  rangeOptions: [...document.querySelectorAll("#visualizationRange option")].map(x => x.value),
  objectSearchPresent: Boolean(document.getElementById("visualizationObjectSearch")),
  startDatePresent: Boolean(document.getElementById("visualizationStartDate")),
  endDatePresent: Boolean(document.getElementById("visualizationEndDate")),
  charts: document.querySelectorAll("#visualizationChart svg").length,
  periodLabels: [...document.querySelectorAll(".kpi-label")].map(x => x.textContent.trim()),
  headers: [...document.querySelectorAll("section:not(.visualization-space) thead th")].map(x => x.textContent.trim()),
  categoryTitle: [...document.querySelectorAll("section h2")].map(x => x.textContent.trim()).find(x => x.startsWith("品类 Top")),
  guildTitle: [...document.querySelectorAll("section h2")].map(x => x.textContent.trim()).find(x => x.startsWith("公会 Top")),
  categoryHeaders: [...document.querySelectorAll("#categoryTable thead th")].map(x => x.textContent.trim()),
  guildHeaders: [...document.querySelectorAll("#guildTable thead th")].map(x => x.textContent.trim()),
  categoryLevelCells: document.querySelectorAll("#categoryTableBody td.severity-高, #categoryTableBody td.severity-中, #categoryTableBody td.severity-低").length,
  guildLevelCells: document.querySelectorAll("#guildTableBody td.severity-高, #guildTableBody td.severity-中, #guildTableBody td.severity-低").length,
  anchorHeaders: [...document.querySelectorAll("#anchorTable thead th")].map(x => x.textContent.trim()),
  anchorLevelCells: document.querySelectorAll("#anchorTableBody td.severity-高, #anchorTableBody td.severity-中, #anchorTableBody td.severity-低").length,
  methodNotesAfterAnchors: Boolean(document.querySelector("#anchorTable") && document.querySelector("#methodNotesTitle") && (document.querySelector("#anchorTable").compareDocumentPosition(document.querySelector("#methodNotesTitle")) & Node.DOCUMENT_POSITION_FOLLOWING)),
  visibleCategoryRows: document.querySelectorAll("#categoryTableBody tr:not([hidden])").length,
  totalCategoryRows: document.querySelectorAll("#categoryTableBody tr").length,
  visibleGuildRows: document.querySelectorAll("#guildTableBody tr:not([hidden])").length,
  totalGuildRows: document.querySelectorAll("#guildTableBody tr").length,
  visibleAnchorRows: document.querySelectorAll("#anchorTableBody tr:not([hidden])").length,
  totalAnchorRows: document.querySelectorAll("#anchorTableBody tr").length
}))()`);

const customRange = await evaluate(`(() => {
  const range=document.getElementById("visualizationRange");
  range.value="custom";range.dispatchEvent(new Event("change",{bubbles:true}));
  const start=document.getElementById("visualizationStartDate");
  const end=document.getElementById("visualizationEndDate");
  start.value="2026-11-01";start.dispatchEvent(new Event("change",{bubbles:true}));
  end.value="2026-11-10";end.dispatchEvent(new Event("change",{bubbles:true}));
  return {range:window.__visualizationDebug.state.range,start:start.value,end:end.value,points:window.__visualizationDebug.aggregateMain().length};
})()`);
await evaluate(`(() => { const range=document.getElementById("visualizationRange"); range.value="all"; range.dispatchEvent(new Event("change",{bubbles:true})); })()`);

const tooltip = await evaluate(`(() => {
  const target=document.querySelector("#visualizationChart [data-tooltip]");
  if(!target)return {found:false,visible:false,text:""};
  target.dispatchEvent(new MouseEvent("pointermove",{bubbles:true,clientX:120,clientY:120}));
  const node=document.getElementById("visualizationTooltip");
  return {found:true,visible:node.classList.contains("visible"),text:node.textContent.trim()};
})()`);

const topN = await evaluate(`(() => {
  const input=document.getElementById("anchorTopLimit");
  if(!input)return {supported:false,visible:0,total:0,title:""};
  input.value="5";input.dispatchEvent(new Event("input",{bubbles:true}));
  return {
    supported:true,
    visible:document.querySelectorAll("#anchorTableBody tr:not([hidden])").length,
    total:document.querySelectorAll("#anchorTableBody tr").length,
    title:document.getElementById("anchorTopTitle")?.textContent.trim()
  };
})()`);

const categoryTopN = await evaluate(`(() => {
  const input=document.getElementById("categoryTopLimit");
  if(!input)return {supported:false,visible:0,total:0,title:""};
  input.value="5";input.dispatchEvent(new Event("input",{bubbles:true}));
  return {
    supported:true,
    visible:document.querySelectorAll("#categoryTableBody tr:not([hidden])").length,
    total:document.querySelectorAll("#categoryTableBody tr").length,
    title:document.getElementById("categoryTopTitle")?.textContent.trim()
  };
})()`);

const guildTopN = await evaluate(`(() => {
  const input=document.getElementById("guildTopLimit");
  if(!input)return {supported:false,visible:0,total:0,title:""};
  input.value="5";input.dispatchEvent(new Event("input",{bubbles:true}));
  return {
    supported:true,
    visible:document.querySelectorAll("#guildTableBody tr:not([hidden])").length,
    total:document.querySelectorAll("#guildTableBody tr").length,
    title:document.getElementById("guildTopTitle")?.textContent.trim()
  };
})()`);

const categoryCompare = await evaluate(`(() => {
  const scope=document.getElementById("visualizationScope");scope.value="total";scope.dispatchEvent(new Event("change",{bubbles:true}));
  const dimension=document.getElementById("visualizationDimension");dimension.value="category";dimension.dispatchEvent(new Event("change",{bubbles:true}));
  const search=document.getElementById("visualizationObjectSearch");search.value="英雄";search.dispatchEvent(new Event("input",{bubbles:true}));
  document.getElementById("visualizationSelectVisible").click();
  search.value="王者荣耀";search.dispatchEvent(new Event("input",{bubbles:true}));
  const option=[...document.querySelectorAll("#visualizationDrillValue [data-object-value]")].find(input=>input.closest("label")?.textContent.includes("王者荣耀"));
  option?.click();
  return {selected:window.__visualizationDebug.getSelected(),legend:[...document.querySelectorAll("#visualizationLegend span")].map(x=>x.textContent.trim()),lines:document.querySelectorAll("#visualizationChart path.line-path").length};
})()`);

const anchorCompare = await evaluate(`(() => {
  const dimension=document.getElementById("visualizationDimension");dimension.value="anchor";dimension.dispatchEvent(new Event("change",{bubbles:true}));
  const options=[...document.querySelectorAll("#visualizationDrillValue [data-object-value]")].filter(input=>input.dataset.objectValue!=="all");
  options[0]?.click();
  const next=[...document.querySelectorAll("#visualizationDrillValue [data-object-value]")].find(input=>input.dataset.objectValue!=="all"&&!input.checked);
  next?.click();
  return {selected:window.__visualizationDebug.getSelected(),anchorRows:window.__visualizationDebug.anchorDataLength,legend:[...document.querySelectorAll("#visualizationLegend span")].map(x=>x.textContent.trim()),lines:document.querySelectorAll("#visualizationChart path.line-path").length,dateMin:document.getElementById("visualizationStartDate").min,dateMax:document.getElementById("visualizationStartDate").max};
})()`);

async function clickChartType(type) {
  await evaluate(`document.querySelector('[data-chart-type="${type}"]').click()`);
  await delay(300);
  return evaluate(`(() => ({
    state: window.__visualizationDebug.state.chartType,
    bars: document.querySelectorAll("#visualizationChart .bar").length,
    stack: document.querySelectorAll("#visualizationChart .stack-segment").length,
    legend: document.querySelectorAll("#visualizationLegend span").length
  }))()`);
}

await evaluate(`(() => { const el=document.getElementById("visualizationScope"); el.value="platform"; el.dispatchEvent(new Event("change",{bubbles:true})); })()`);
const bar = await clickChartType("bar");
const stackPlatform = await clickChartType("stack");
await evaluate(`(() => { const el=document.getElementById("visualizationScope"); el.value="total"; el.dispatchEvent(new Event("change",{bubbles:true})); })()`);
await delay(300);
const stackTotal = await evaluate(`(() => ({
  stack: document.querySelectorAll("#visualizationChart .stack-segment").length,
  legend: [...document.querySelectorAll("#visualizationLegend span")].map(x => x.textContent.trim()),
  drillGroups: document.querySelectorAll('#visualizationChart [data-drill-dim="group"]').length
}))()`);
const drillClick = await evaluate(`(() => {
  const target=document.querySelector('#visualizationChart [data-drill-dim="group"]');
  if(!target)return {found:false,dimension:"",value:"",state:window.__visualizationDebug.state.drill};
  const detail={found:true,dimension:target.dataset.drillDim,value:target.dataset.drillValue};
  target.dispatchEvent(new MouseEvent("click",{bubbles:true}));
  return {...detail,state:window.__visualizationDebug.state.drill};
})()`);
await delay(300);
const drilledGroup = await evaluate(`(() => ({
  scope: window.__visualizationDebug.state.scope,
  dimension: window.__visualizationDebug.state.dimension,
  drill: window.__visualizationDebug.state.drill,
  breadcrumb: document.getElementById("visualizationBreadcrumb").textContent.replace(/\s+/g," ").trim(),
  legend: [...document.querySelectorAll("#visualizationLegend span")].map(x => x.textContent.trim())
}))()`);
await evaluate(`(() => { const el=document.getElementById("visualizationGranularity"); el.value="month"; el.dispatchEvent(new Event("change",{bubbles:true})); })()`);
await delay(250);
const monthly = await evaluate(`(() => ({type:window.__visualizationDebug.state.chartType,large:document.querySelectorAll("#visualizationChart .stack-segment").length,breadcrumb:document.getElementById("visualizationBreadcrumb").textContent.replace(/\s+/g," ").trim()}))()`);

const checks = {
  initialized: initial.ready && initial.rows > 0 && initial.scopeOptions === 2 && initial.charts === 1,
  analysisScopeIsPlatformAndEcosystem: initial.scopeLabels.some(label => label.includes("平台 DAU")) && initial.scopeLabels.some(label => label.includes("内容生态 DAU")) && initial.scopeLabels.every(label => !label.includes("内容大类") && !label.includes("品类 ·")),
  drillDimensionsAvailable: initial.dimensionOptions.join(",") === "none,group,category,anchor" && initial.dimensionDisabled === true,
  defaultPlatformDaily: initial.scope === "platform" && initial.dimension === "none" && initial.granularity === "day" && initial.chartType === "line",
  explicitPeriodLabels: initial.periodLabels.every(label => label.endsWith("（日）")) && initial.headers.includes("最新完整周 DAU（7 日求和）"),
  configurableCategoryTopN: categoryTopN.supported && initial.categoryTitle === "品类 Top10" && initial.visibleCategoryRows === 10 && initial.totalCategoryRows === 50 && categoryTopN.visible === 5 && categoryTopN.title === "品类 Top5",
  configurableGuildTopN: guildTopN.supported && initial.guildTitle === "公会 Top20" && initial.visibleGuildRows === 20 && initial.totalGuildRows === 50 && guildTopN.visible === 5 && guildTopN.title === "公会 Top5",
  guildSelfLevel: initial.guildHeaders.includes("级别") && initial.guildLevelCells === initial.totalGuildRows,
  anchorSelfLevel: initial.anchorHeaders.includes("级别") && initial.anchorLevelCells === initial.totalAnchorRows,
  guildLiveAnchors: initial.headers.includes("最新完整周 开播主播数（日均）") && initial.headers.includes("上一完整周 开播主播数（日均）"),
  tooltipVisible: tooltip.found && tooltip.visible && tooltip.text.length > 0,
  customTimeRange: initial.rangeOptions.includes("custom") && initial.startDatePresent && initial.endDatePresent && customRange.range === "custom" && customRange.start === "2026-11-01" && customRange.end === "2026-11-10" && customRange.points === 10,
  fuzzyMultiCategoryCompare: categoryCompare.selected.length >= 2 && categoryCompare.legend.length >= 2 && categoryCompare.lines >= 2,
  anchorMultiCompareReady: initial.anchorRows > 0 && anchorCompare.anchorRows > 0 && anchorCompare.selected.length === 2 && anchorCompare.legend.length === 2 && anchorCompare.lines >= 2 && anchorCompare.dateMin === "2026-10-12" && anchorCompare.dateMax === "2026-11-22",
  customAnchorTopN: topN.supported && topN.total >= 5 && topN.visible === 5 && topN.title === "主播 Top5",
  methodNotesAtBottom: initial.methodNotesAfterAnchors,
  barRendered: bar.state === "bar" && bar.bars > 0,
  platformStackRendered: stackPlatform.state === "stack" && stackPlatform.stack > 0 && stackPlatform.legend === 1,
  totalStackComposition: stackTotal.stack > 0 && stackTotal.legend.length >= 3 && stackTotal.drillGroups > 0,
  categoryDrilldown: drilledGroup.scope === "total" && drilledGroup.dimension === "group" && drilledGroup.drill !== "all" && drilledGroup.breadcrumb.includes("›") && drilledGroup.legend.length >= 1,
  monthlyStack: monthly.large > 0 && monthly.breadcrumb.includes("›"),
  noRuntimeExceptions: exceptions.length === 0,
};

console.log(JSON.stringify({ status: Object.values(checks).every(Boolean) ? "passed" : "failed", checks, initial, customRange, tooltip, topN, categoryTopN, guildTopN, categoryCompare, anchorCompare, bar, stackPlatform, stackTotal, drillClick, drilledGroup, monthly, exceptions }, null, 2));
ws.close();
if (!Object.values(checks).every(Boolean)) process.exitCode = 1;
