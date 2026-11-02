# 加密凭据保险包

`migration-secrets-v2.aesgcm` 是本迁移包当前应使用的完整凭据副本，使用 AES-256-GCM 加密。当前内容包含：

- 用户目录下发现的 4 个实际 `.env` 文件。
- 从 AGENTS 附件核对的虎牙数据平台账号和 API 凭据，路径为 `credentials/bigdata-platform.txt`。
- 原 DAU 告警脚本中的 SMTP 账号/密码、3 个企业微信 webhook、HDFS 用户身份与来源引用，路径为 `credentials/huya-alert-mail-credentials.txt`。
- 从原告警脚本逐行提取的内部收件路由，路径为 `credentials/huya-alert-recipient-routing.txt`；仅验证收件人仍获授权后才能恢复。
- 凭据恢复说明 `credentials/README.txt`、`credentials/huya-alert-mail-readme.txt`。

GitHub 密码在聊天中暴露，并且用户计划修改，因此没有归档旧密码。GitHub 重新登录应使用设备授权或新的最小权限 token。

## 解密

密钥文件 `huya_ty-env-files.key` 保存在仓库之外。只应通过加密介质或密码管理器转移到新电脑，不要上传 GitHub。

```powershell
node vault/decrypt-env-files.mjs vault/migration-secrets-v2.aesgcm <key-file> <new-staging-directory>
```

解密脚本会在暂存目录写入 `manifest.json`，并对每个文件校验 SHA-256。目标目录必须为空；脚本不会覆盖已有文件。

恢复后：

1. 将 `.env` 内容移入凭据管理器或对应工具的安全配置，不要留在 Git 仓库。
2. 将虎牙数据平台凭据写入 bigdata MCP 的安全凭据配置。
3. 完成验证后删除明文暂存目录。
4. 轮换聊天中暴露过的 GitHub 密码和数据平台 API key，再重新加密保险包。

## 重新加密

`encrypt-env-files.mjs` 把一个只含待加密文件的暂存目录封装为新保险包，并拒绝覆盖已有保险包：

```powershell
node vault/encrypt-env-files.mjs <staging-directory> <key-file> <new-archive-file>
```

`add-source-credentials.mjs` 用于把 AGENTS 附件中的数据平台凭据合并进第二版保险包。`add-alert-mail-credentials.mjs` 再把原告警脚本中的 SMTP、企业微信、HDFS 身份和收件路由合并进第三版保险包。两个脚本都只在内存中解密和重新加密，不把明文凭据写入仓库。虽然原告警项目已按用户要求跳过复盘，凭据仍按用户的完整凭据迁移要求单独保留。

`migration-secrets.aesgcm` 是未包含 DAU 告警凭据的上一版，`env-files.aesgcm` 仅包含 `.env` 文件；两者都只保留作历史副本。新电脑必须优先使用 `migration-secrets-v2.aesgcm`。告警脚本曾明文保存 SMTP 密码和 webhook，恢复前应轮换。

英文版见 `README.en.md`。
