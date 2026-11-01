import crypto from "node:crypto";
import fs from "node:fs";
import zlib from "node:zlib";

const [sourceArchive, keyPath, credentialSource, outputArchive] = process.argv.slice(2);
if (!sourceArchive || !keyPath || !credentialSource || !outputArchive) {
  throw new Error(
    "Usage: node add-source-credentials.mjs <source-archive> <key-file> <credential-source> <output-archive>",
  );
}
if (fs.existsSync(outputArchive)) throw new Error("Refusing to overwrite " + outputArchive);

const keyHex = fs.readFileSync(keyPath, "utf8").trim();
if (!/^[0-9a-f]{64}$/i.test(keyHex)) throw new Error("Invalid key file");
const key = Buffer.from(keyHex, "hex");

function decryptArchive(archivePath) {
  const envelope = JSON.parse(fs.readFileSync(archivePath, "utf8"));
  if (envelope.format !== "huya_ty-env-files-aesgcm-v1" || envelope.algorithm !== "AES-256-GCM") {
    throw new Error("Unsupported encrypted bundle format");
  }
  const decipher = crypto.createDecipheriv(
    "aes-256-gcm",
    key,
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
  return payload;
}

function encryptArchive(payload, archivePath) {
  const compressed = zlib.gzipSync(Buffer.from(JSON.stringify(payload), "utf8"));
  const iv = crypto.randomBytes(12);
  const aad = "huya_ty-env-files-v1";
  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
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
  fs.writeFileSync(archivePath, JSON.stringify(envelope, null, 2) + "\n", { flag: "wx" });
}

function makeFile(relativePath, text) {
  const content = Buffer.from(text, "utf8");
  return {
    sourcePath: relativePath,
    relativePath,
    sha256: crypto.createHash("sha256").update(content).digest("hex"),
    content: content.toString("base64"),
  };
}

const attachmentText = fs.readFileSync(credentialSource, "utf8").replace(/^\uFEFF/, "");
const match = attachmentText.match(/账号\s*[:：]\s*(dw_[A-Za-z0-9_]+)\s+api秘钥\s*[:：]\s*([A-Za-z0-9]+)/i);
if (!match) throw new Error("Could not locate the bigdata credential in the source attachment");

const payload = decryptArchive(sourceArchive);
const additions = [
  makeFile(
    "credentials/bigdata-platform.txt",
    [
      "[huya_bigdata]",
      `username=${match[1]}`,
      `api_key=${match[2]}`,
      "source=Pasted AGENTS.md attachment",
      "restore=Store in the new computer's secure credential store.",
      "warning=Rotate this key before sharing the migration package outside the user's control.",
      "",
    ].join("\n"),
  ),
  makeFile(
    "credentials/README.txt",
    [
      "Credential recovery notes",
      "- Restore .env files to their original relative paths only after confirming each target.",
      "- Store the bigdata MCP credential in the client credential store; do not copy it into AGENTS.md, SQL, or Git-tracked files.",
      "- The GitHub account password was exposed in chat and is scheduled for rotation. It is intentionally not archived; after rotation, authenticate with a device flow or a new scoped token.",
      "",
    ].join("\n"),
  ),
];

for (const file of additions) {
  if (payload.files.some((existing) => existing.relativePath === file.relativePath)) {
    throw new Error("Duplicate vault path: " + file.relativePath);
  }
  payload.files.push(file);
}
payload.files.sort((a, b) => a.relativePath.localeCompare(b.relativePath));
encryptArchive(payload, outputArchive);

const verified = decryptArchive(outputArchive);
if (verified.files.length !== payload.files.length) throw new Error("Verification file count mismatch");
for (const file of verified.files) {
  const digest = crypto.createHash("sha256").update(Buffer.from(file.content, "base64")).digest("hex");
  if (digest !== file.sha256) throw new Error("Verification hash mismatch: " + file.relativePath);
}
console.log(
  JSON.stringify({
    archive: outputArchive,
    files: verified.files.map((file) => file.relativePath),
  }),
);
