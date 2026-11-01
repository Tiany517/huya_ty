import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const P = "C:/Users/tiany/Desktop/AI工坊专题/AI工坊_版本周日均转换率_20260713-20260914.xlsx";
const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(P));

const sheets = await wb.inspect({ kind: "sheet", include: "id,name" });
console.log(sheets.ndjson);

for (const [name, range] of [
  ["版本周日均转换率", "A2:J16"],
  ["版本窗口曝光占比", "A2:L14"],
  ["版本周明细", "A1:L51"],
  ["口径说明", "A1:B20"],
]) {
  const r = await wb.inspect({ kind: "table", sheetId: name, range, include: "values", tableMaxRows: 60, tableMaxCols: 14, maxChars: 6000 });
  console.log("=== " + name + " ===");
  console.log(r.ndjson);
}

const err = await wb.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!",
  options: { useRegex: true, maxResults: 100 },
});
console.log("=== errors ===");
console.log(err.ndjson);

const outDir = "C:/Users/tiany/Desktop/AI工坊专题/_verify_png";
await fs.mkdir(outDir, { recursive: true });
for (const name of ["版本周日均转换率", "版本窗口曝光占比"]) {
  const blob = await wb.render({ sheetName: name, autoCrop: "all", scale: 2, format: "png" });
  await fs.writeFile(outDir + "/" + name + ".png", new Uint8Array(await blob.arrayBuffer()));
}
console.log("rendered");
