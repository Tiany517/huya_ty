import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

function argsMap() {
  const result = {};
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i += 1) {
    if (!argv[i].startsWith("--")) continue;
    const key = argv[i].slice(2);
    const value = argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[++i] : true;
    result[key] = value;
  }
  return result;
}

function findChrome(explicit) {
  if (explicit) return explicit;
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH;
  const candidates = [
    "C:/Program Files/Google/Chrome/Application/chrome.exe",
    "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
    `${process.env.LOCALAPPDATA || ""}/Google/Chrome/Application/chrome.exe`,
    "C:/Program Files/Microsoft/Edge/Application/msedge.exe",
    "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  ];
  return candidates.find(candidate => candidate && fs.existsSync(candidate));
}

const args = argsMap();
if (!args.html) throw new Error("usage: node smoke_test_dashboard.mjs --html <dashboard.html> [--chrome <path>] [--report <json>]");
const htmlPath = path.resolve(args.html);
if (!fs.existsSync(htmlPath)) throw new Error(`dashboard not found: ${htmlPath}`);
const chrome = findChrome(args.chrome);
if (!chrome) throw new Error("Chrome/Edge not found; set CHROME_PATH or pass --chrome");

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "ecology-dashboard-smoke-"));
const url = pathToFileURL(htmlPath).href;
const commandArgs = [
  "--headless=new",
  "--disable-gpu",
  "--disable-extensions",
  "--no-first-run",
  "--allow-file-access-from-files",
  "--virtual-time-budget=15000",
  `--user-data-dir=${profile}`,
  "--dump-dom",
  url,
];

const result = await new Promise((resolve, reject) => {
  const child = spawn(chrome, commandArgs, { stdio: ["ignore", "pipe", "pipe"] });
  let stdout = "";
  let stderr = "";
  const timer = setTimeout(() => {
    child.kill("SIGKILL");
    reject(new Error("dashboard smoke test timed out after 60 seconds"));
  }, 60_000);
  child.stdout.on("data", chunk => { stdout += chunk.toString("utf8"); });
  child.stderr.on("data", chunk => { stderr += chunk.toString("utf8"); });
  child.on("error", error => { clearTimeout(timer); reject(error); });
  child.on("close", code => { clearTimeout(timer); resolve({ code, stdout, stderr }); });
});

fs.rmSync(profile, { recursive: true, force: true });
const checks = {
  processExitZero: result.code === 0,
  dashboardTitleRendered: result.stdout.includes("生态监控"),
  rankingRendered: result.stdout.includes("Top20"),
  loadingCleared: !result.stdout.includes("正在读取多维度看板数据"),
};
const report = {
  status: Object.values(checks).every(Boolean) ? "passed" : "failed",
  html: htmlPath,
  chrome,
  checks,
  domBytes: Buffer.byteLength(result.stdout, "utf8"),
  stderrTail: result.stderr.slice(-4000),
};
if (args.report) {
  const reportPath = path.resolve(args.report);
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
}
console.log(JSON.stringify(report, null, 2));
if (report.status !== "passed") process.exitCode = 1;
