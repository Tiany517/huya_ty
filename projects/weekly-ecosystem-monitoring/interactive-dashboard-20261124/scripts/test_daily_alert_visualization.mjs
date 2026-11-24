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
  granularity: window.__visualizationDebug?.state.granularity,
  chartType: window.__visualizationDebug?.state.chartType,
  rows: window.__visualizationDebug?.dataLength || 0,
  scopeOptions: document.querySelectorAll("#visualizationScope option").length,
  charts: document.querySelectorAll("#visualizationChart svg").length,
  periodLabels: [...document.querySelectorAll(".kpi-label")].map(x => x.textContent.trim()),
  headers: [...document.querySelectorAll("section:not(.visualization-space) thead th")].map(x => x.textContent.trim())
}))()`);

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
  drillGroups: document.querySelectorAll("#visualizationChart [data-drill-group]").length
}))()`);
await evaluate(`document.querySelector("#visualizationChart [data-drill-group]")?.dispatchEvent(new MouseEvent("click",{bubbles:true}))`);
await delay(300);
const drilledGroup = await evaluate(`(() => ({
  scope: window.__visualizationDebug.state.scope,
  breadcrumb: document.getElementById("visualizationBreadcrumb").textContent.replace(/\s+/g," ").trim(),
  legend: [...document.querySelectorAll("#visualizationLegend span")].map(x => x.textContent.trim())
}))()`);
await evaluate(`(() => { const el=document.getElementById("visualizationGranularity"); el.value="month"; el.dispatchEvent(new Event("change",{bubbles:true})); })()`);
await delay(250);
const monthly = await evaluate(`(() => ({type:window.__visualizationDebug.state.chartType,large:document.querySelectorAll("#visualizationChart .stack-segment").length,breadcrumb:document.getElementById("visualizationBreadcrumb").textContent.replace(/\s+/g," ").trim()}))()`);

const checks = {
  initialized: initial.ready && initial.rows > 0 && initial.scopeOptions >= 4 && initial.charts === 1,
  defaultPlatformDaily: initial.scope === "platform" && initial.granularity === "day" && initial.chartType === "line",
  explicitPeriodLabels: initial.periodLabels.every(label => label.endsWith("（日）")) && initial.headers.includes("最新完整周 DAU（7 日求和）"),
  barRendered: bar.state === "bar" && bar.bars > 0,
  platformStackRendered: stackPlatform.state === "stack" && stackPlatform.stack > 0,
  totalStackComposition: stackTotal.stack > 0 && stackTotal.legend.length >= 3 && stackTotal.drillGroups > 0,
  categoryDrilldown: drilledGroup.scope.startsWith("group:") && drilledGroup.breadcrumb.includes("›") && drilledGroup.legend.length >= 2,
  monthlyStack: monthly.large > 0 && monthly.breadcrumb.includes("›"),
  noRuntimeExceptions: exceptions.length === 0,
};

console.log(JSON.stringify({ status: Object.values(checks).every(Boolean) ? "passed" : "failed", checks, initial, bar, stackPlatform, stackTotal, drilledGroup, monthly, exceptions }, null, 2));
ws.close();
if (!Object.values(checks).every(Boolean)) process.exitCode = 1;
