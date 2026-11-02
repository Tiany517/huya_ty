# Codex 本地工作记录摘要备份

## 为什么需要它

当前 ChatGPT 使用公司提供的 API/工作区。公司 API 账号不等于普通 ChatGPT 网页账号，不能假设网页端的“导出数据”会覆盖这里的 Codex 工作记录。本机也没有找到官方的 `conversations.json`、`chat.html` 或 OpenAI 导出压缩包。

因此，本项目从本机 Codex 数据库生成一份可迁移的工作记录摘要，并使用与凭据保险包相同的 AES-256-GCM 密钥加密。

加密文件：`archive/codex-work-history/codex-work-history-20261102.aesgcm`

## 包含内容

- 300 个有可保留消息的本地 Codex 线程标题、时间范围和回合状态。
- 3,453 条用户请求和 6,962 条助手最终/无阶段标记答复，按线程和发生时间保存为 `threads.jsonl`。
- 便于检索的 `thread-catalog.csv`。
- `session-index.jsonl` 中的线程索引。
- `.codex/memories/` 中的记忆摘要、可检索记忆、原始记忆索引和 rollout summaries。
- `archive-metadata.json`：导出时间、数量、排除范围、文件 SHA-256。

## 明确排除

- 推理过程、commentary 中间更新、命令执行轨迹、工具参数/输出、图片二进制、文件 diff 和缓存。
- 完整 `thread_history_1.sqlite`、`logs_2.sqlite` 和 933 MB 的原始 session/archived-session 目录，避免把数百 MB 工具日志推入 Git。
- 自动“memory agent”观察器生成的内部提示词。

这些排除项降低体积和噪声，但工作请求、关键结论和本地记忆仍然保留。项目源 SQL、结果文件和 skills 另有独立 GitHub 路径。

## 解密与使用

密钥文件 `huya_ty-env-files.key` 仍在仓库外，只通过加密介质或密码管理器转移到新电脑。

```powershell
node vault/decrypt-env-files.mjs archive/codex-work-history/codex-work-history-20261102.aesgcm <key-file> <new-staging-directory>
```

解密后先读 `archive-metadata.json` 和 `thread-catalog.csv`，再按线程搜索 `threads.jsonl`。`memory/` 用于恢复工作习惯、历史口径和既往排错经验。

## GitHub 路径地图

| GitHub 路径 | 内容 |
| --- | --- |
| `archive/codex-work-history/README.md` | 中文说明 |
| `archive/codex-work-history/README.en.md` | 英文说明 |
| `archive/codex-work-history/export_local_history.py` | 可重复生成本地摘要的导出脚本 |
| `archive/codex-work-history/codex-work-history-20261102.aesgcm` | 加密后的工作记录与本地记忆摘要 |

以上路径均相对于 GitHub 仓库根目录。
