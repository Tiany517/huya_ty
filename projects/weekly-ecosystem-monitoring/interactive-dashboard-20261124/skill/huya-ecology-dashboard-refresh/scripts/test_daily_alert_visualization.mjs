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
  scopeOptions: document.querySelectorAll("#visualizationScope option").length,
  scopeLabels: [...document.querySelectorAll("#visualizationScope option")].map(x => x.textContent.trim()),
  dimensionOptions: [...document.querySelectorAll("#visualizationDimension option")].map(x => x.value),
  dimensionDisabled: document.getElementById("visualizationDimension")?.disabled,
  charts: document.querySelectorAll("#visualizationChart svg").length,
  periodLabels: [...document.querySelectorAll(".kpi-label")].map(x => x.textContent.trim()),
  headers: [...document.querySelectorAll("section:not(.visualization-space) thead th")].map(x => x.textContent.trim()),
  categoryTitle: [...document.querySelectorAll("section h2")].map(x => x.textContent.trim()).find(x => x.startsWith("品类 Top")),
  methodNotesAfterAnchors: Boolean(document.querySelector("#anchorTable") && document.querySelector("#methodNotesTitle") && (document.querySelector("#anchorTable").compareDocumentPosition(document.querySelector("#methodNotesTitle")) & Node.DOCUMENT_POSITION_FOLLOWING)),
  visibleAnchorRows: document.querySelectorAll("#anchorTableBody tr:not([hidden])").length,
  totalAnchorRows: document.querySelectorAll("#anchorTableBody tr").length
}))()`);

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
  drillDimensionsAvailable: initial.dimensionOptions.join(",") === "none,group,category" && initial.dimensionDisabled === true,
  defaultPlatformDaily: initial.scope === "platform" && initial.dimension === "none" && initial.granularity === "day" && initial.chartType === "line",
  explicitPeriodLabels: initial.periodLabels.every(label => label.endsWith("（日）")) && initial.headers.includes("最新完整周 DAU（7 日求和）"),
  categoryTop10: initial.categoryTitle === "品类 Top10",
  guildLiveAnchors: initial.headers.includes("最新完整周 开播主播数（日均）") && initial.headers.includes("上一完整周 开播主播数（日均）"),
  tooltipVisible: tooltip.found && tooltip.visible && tooltip.text.length > 0,
  customAnchorTopN: topN.supported && topN.total >= 5 && topN.visible === 5 && topN.title === "主播 Top5",
  methodNotesAtBottom: initial.methodNotesAfterAnchors,
  barRendered: bar.state === "bar" && bar.bars > 0,
  platformStackRendered: stackPlatform.state === "stack" && stackPlatform.stack > 0 && stackPlatform.legend === 1,
  totalStackComposition: stackTotal.stack > 0 && stackTotal.legend.length >= 3 && stackTotal.drillGroups > 0,
  categoryDrilldown: drilledGroup.scope === "total" && drilledGroup.dimension === "group" && drilledGroup.drill !== "all" && drilledGroup.breadcrumb.includes("›") && drilledGroup.legend.length >= 2,
  monthlyStack: monthly.large > 0 && monthly.breadcrumb.includes("›"),
  noRuntimeExceptions: exceptions.length === 0,
};

console.log(JSON.stringify({ status: Object.values(checks).every(Boolean) ? "passed" : "failed", checks, initial, tooltip, topN, bar, stackPlatform, stackTotal, drillClick, drilledGroup, monthly, exceptions }, null, 2));
ws.close();
if (!Object.values(checks).every(Boolean)) process.exitCode = 1;
