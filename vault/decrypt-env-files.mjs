import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

const [archivePath, keyPath, outputDir] = process.argv.slice(2);
if (!archivePath || !keyPath || !outputDir) {
  throw new Error("Usage: node decrypt-env-files.mjs <archive> <key-file> <staging-directory>");
}

const envelope = JSON.parse(fs.readFileSync(archivePath, "utf8"));
if (envelope.format !== "huya_ty-env-files-aesgcm-v1" || envelope.algorithm !== "AES-256-GCM") {
  throw new Error("Unsupported encrypted bundle format");
}

const keyHex = fs.readFileSync(keyPath, "utf8").trim();
if (!/^[0-9a-f]{64}$/i.test(keyHex)) throw new Error("Invalid key file");

const decipher = crypto.createDecipheriv(
  "aes-256-gcm",
  Buffer.from(keyHex, "hex"),
  Buffer.from(envelope.iv, "base64"),
);
decipher.setAAD(Buffer.from(envelope.aad, "utf8"));
decipher.setAuthTag(Buffer.from(envelope.tag, "base64"));
const compressed = Buffer.concat([
  decipher.update(Buffer.from(envelope.ciphertext, "base64")),
  decipher.final(),
]);
const payload = JSON.parse(zlib.gunzipSync(compressed).toString("utf8"));
if (payload.format !== "huya_ty-env-files-v1" || !Array.isArray(payload.files)) {
  throw new Error("Invalid decrypted payload");
}

const root = path.resolve(outputDir);
const manifestPath = path.join(root, "manifest.json");
const restored = payload.files.map((file) => {
  const relativePath = file.relativePath.split("/").join(path.sep);
  const targetPath = path.resolve(root, relativePath);
  if (!targetPath.startsWith(root + path.sep)) throw new Error("Unsafe path in bundle");
  const content = Buffer.from(file.content, "base64");
  const digest = crypto.createHash("sha256").update(content).digest("hex");
  if (digest !== file.sha256) throw new Error("Integrity check failed for " + file.relativePath);
  return { ...file, targetPath, content };
});

for (const file of restored) {
  if (fs.existsSync(file.targetPath)) throw new Error("Refusing to overwrite " + file.targetPath);
}
if (fs.existsSync(manifestPath)) throw new Error("Refusing to overwrite " + manifestPath);

fs.mkdirSync(root, { recursive: true });
for (const file of restored) {
  fs.mkdirSync(path.dirname(file.targetPath), { recursive: true });
  fs.writeFileSync(file.targetPath, file.content, { flag: "wx" });
}
fs.writeFileSync(
  manifestPath,
  JSON.stringify(
    restored.map(({ sourcePath, relativePath, sha256 }) => ({ sourcePath, relativePath, sha256 })),
    null,
    2,
  ) + "\n",
  { flag: "wx" },
);
console.log("Restored " + restored.length + " files to the staging directory.");
