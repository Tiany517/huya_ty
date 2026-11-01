import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

const [inputDir, keyPath, archivePath] = process.argv.slice(2);
if (!inputDir || !keyPath || !archivePath) {
  throw new Error("Usage: node encrypt-env-files.mjs <staging-directory> <key-file> <archive>");
}

const keyHex = fs.readFileSync(keyPath, "utf8").trim();
if (!/^[0-9a-f]{64}$/i.test(keyHex)) throw new Error("Invalid key file");

const root = path.resolve(inputDir);
if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
  throw new Error("Staging directory does not exist: " + root);
}

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) throw new Error("Refusing to archive symlink: " + fullPath);
    return entry.isDirectory() ? walk(fullPath) : [fullPath];
  });
}

const files = walk(root)
  .sort()
  .map((fullPath) => {
    const content = fs.readFileSync(fullPath);
    const relativePath = path.relative(root, fullPath).split(path.sep).join("/");
    if (relativePath === "manifest.json") throw new Error("Remove manifest.json before encryption");
    return {
      sourcePath: relativePath,
      relativePath,
      sha256: crypto.createHash("sha256").update(content).digest("hex"),
      content: content.toString("base64"),
    };
  });

if (files.length === 0) throw new Error("No files found to encrypt");

const payload = Buffer.from(
  JSON.stringify({ format: "huya_ty-env-files-v1", files }),
  "utf8",
);
const compressed = zlib.gzipSync(payload);
const iv = crypto.randomBytes(12);
const aad = "huya_ty-env-files-v1";
const cipher = crypto.createCipheriv("aes-256-gcm", Buffer.from(keyHex, "hex"), iv);
cipher.setAAD(Buffer.from(aad, "utf8"));
const ciphertext = Buffer.concat([cipher.update(compressed), cipher.final()]);
const envelope = {
  format: "huya_ty-env-files-aesgcm-v1",
  algorithm: "AES-256-GCM",
  aad,
  iv: iv.toString("base64"),
  tag: cipher.getAuthTag().toString("base64"),
  ciphertext: ciphertext.toString("base64"),
};

fs.mkdirSync(path.dirname(path.resolve(archivePath)), { recursive: true });
fs.writeFileSync(archivePath, JSON.stringify(envelope, null, 2) + "\n", { flag: "wx" });
console.log(`Encrypted ${files.length} files to ${archivePath}`);
