import crypto from "node:crypto";
import fs from "node:fs";
import zlib from "node:zlib";
import { execFileSync } from "node:child_process";

const [sourceArchive, keyPath, baseArchive, outputArchive] = process.argv.slice(2);
if (!sourceArchive || !keyPath || !baseArchive || !outputArchive) {
  throw new Error(
    "Usage: node add-alert-mail-credentials.mjs <source-archive> <key-file> <base-vault> <output-vault>",
  );
}
if (!fs.existsSync(sourceArchive)) throw new Error("Source archive does not exist: " + sourceArchive);
if (!fs.existsSync(baseArchive)) throw new Error("Base vault does not exist: " + baseArchive);
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

const memberNames = execFileSync("tar", ["-tzf", sourceArchive], {
  encoding: "utf8",
  maxBuffer: 32 * 1024 * 1024,
})
  .split(/\r?\n/)
  .filter((name) => name.startsWith("mailall/") && name.endsWith(".py"));

const smtpUsers = new Set();
const smtpPasswords = new Set();
const webhooks = new Set();
const hadoopUsers = new Set();
const recipientLines = [];
const credentialSourceRefs = [];
const huyaEmailDomain = ["@", "huya", ".com"].join("");

for (const member of memberNames) {
  const text = execFileSync("tar", ["-xOf", sourceArchive, member], {
    encoding: "utf8",
    maxBuffer: 8 * 1024 * 1024,
  });
  for (const match of text.matchAll(/smtp_user\s*=\s*'([^']+)'/g)) smtpUsers.add(match[1]);
  for (const match of text.matchAll(/smtp_password\s*=\s*'([^']+)'/g)) smtpPasswords.add(match[1]);
  for (const match of text.matchAll(/https:\/\/qyapi\.weixin\.qq\.com\/cgi-bin\/webhook\/send\?key=[A-Za-z0-9-]+/g)) {
    webhooks.add(match[0]);
  }
  for (const match of text.matchAll(/HADOOP_USER_NAME=([^;\\\r\n]+)/g)) hadoopUsers.add(match[1]);
  text.split(/\r?\n/).forEach((line, index) => {
    if (line.includes(huyaEmailDomain)) recipientLines.push(`${member}:${index + 1}: ${line}`);
  });
  if (/smtp_password\s*=|webhook\/send\?key=|HADOOP_USER_NAME=/.test(text)) {
    credentialSourceRefs.push(member);
  }
}

if (smtpPasswords.size === 0) throw new Error("No SMTP credential was found in the source archive");

const archiveSha = crypto.createHash("sha256").update(fs.readFileSync(sourceArchive)).digest("hex");
const credentialText = [
  "Huya DAU alerting credentials",
  `source_archive=${sourceArchive.split(/[\\/]/).pop()}`,
  `source_archive_sha256=${archiveSha}`,
  "warning=The source archive stored these values in plaintext. Rotate them before reuse.",
  "",
  "[smtp]",
  ...[...smtpUsers].sort().map((value) => `user=${value}`),
  ...[...smtpPasswords].sort().map((value) => `password=${value}`),
  "",
  "[hadoop]",
  ...[...hadoopUsers].sort().map((value) => `user=${value}`),
  "",
  "[wecom_webhook]",
  ...[...webhooks].sort().map((value, index) => `observed_${index + 1}=${value}`),
  "",
  "[source_references]",
  ...credentialSourceRefs.sort(),
  "",
].join("\n");

const payload = decryptArchive(baseArchive);
const additions = [
  makeFile("credentials/huya-alert-mail-credentials.txt", credentialText),
  makeFile(
    "credentials/huya-alert-recipient-routing.txt",
    [
      "Internal recipient routing extracted from the Huya DAU alert source archive.",
      "This file is encrypted and must not be copied into Git.",
      "Before reuse, confirm current ownership, approval, and recipient lists.",
      "",
      ...recipientLines,
      "",
    ].join("\n"),
  ),
  makeFile(
    "credentials/huya-alert-mail-readme.txt",
    [
      "Huya DAU alerting credential notes",
      "- Set HADOOP_USER_NAME, SMTP_USER, SMTP_PASSWORD, and WEIXIN_WEBHOOK_URL from this vault only in the runtime environment.",
      "- Rebuild recipient routing from the encrypted routing file after confirming that every recipient is still authorized.",
      "- Rotate the SMTP password and all observed WeCom webhooks because the source archive contained them in plaintext.",
      "- Do not place these values in AGENTS.md, SQL, scripts, shell history, Git, screenshots, or chat.",
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
    files: verified.files.length,
    added: additions.map((file) => file.relativePath),
    smtp_users: smtpUsers.size,
    smtp_passwords: smtpPasswords.size,
    wecom_webhooks: webhooks.size,
    hadoop_users: hadoopUsers.size,
    recipient_lines: recipientLines.length,
  }),
);
