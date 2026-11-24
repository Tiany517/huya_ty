import fs from "node:fs";

const template = fs.readFileSync(new URL("../assets/dashboard_template_multidim.html", import.meta.url), "utf8");

const checks = {
  liquidGlassSurface: template.includes("backdrop-filter") && template.includes("@keyframes liquidFloat"),
  reducedMotion: template.includes("prefers-reduced-motion"),
  chartTypeControls: ["line", "bar", "stack"].every(type => template.includes(`data-chart-type="${type}"`)),
  stackedRenderer: template.includes("function stackedSvg") && template.includes("state.chartType"),
  freeChartCanvas: template.includes('data-visualization-canvas="true"'),
};

console.log(JSON.stringify({ status: Object.values(checks).every(Boolean) ? "passed" : "failed", checks }, null, 2));
if (!Object.values(checks).every(Boolean)) process.exitCode = 1;
