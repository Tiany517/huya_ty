# Migration Inventory

Status: initial read-only discovery on 2026-11-01. No source files have been moved or overwritten. Project categories below are inferred from folder names and still need content and context review.

## Working Rules

| Candidate | Current source | Status |
| --- | --- | --- |
| Data-analysis working rules | `instructions/AGENTS.md` is based on the attached text; its credential-bearing line was replaced with a secure-storage instruction | Needs confirmation |
| Desktop AGENTS version | `Desktop/agents_md/AGENTS.md` | Differs from the attachment; retained for comparison |
| Codex and Claude rules | `.codex/AGENTS.md`, `.claude/AGENTS.md` | Compare before merging |

The attachment matches the AGENTS content shared in this conversation. Compared with the Desktop version, it adds two rules; one contained a plaintext API credential and has been replaced in the migration copy with a secure-storage instruction.

## SQL

The SQL source contains 240 `.sql` files and 2 SQL-formatted `.txt` files, now copied under their original names into `sql/source/`. It also contains 54 CSV files, 22 Excel files, and 25 Python scripts. Result data was not copied; the Python scripts and `content_categories_full.txt` remain queued for project review. Review important results individually; detailed user-level Excel remains out under the original boundary.

## Skills

There are 155 skill folders across Codex, Claude, and shared-agent configuration roots. A total of 1,182 source files were copied by source; 1,088 skill files are tracked in the repository, retaining same-named copies and references. Another 94 files ignored by source `.gitignore` files were not pushed. The `douyin-playwright` folder has Excel files, scripts, images, and temporary JSON that may be project results; review whether to include them under a project directory. Common credential formats were not found; test tokens and environment-variable examples remain unchanged.

## Project Review Candidates

These candidates are based only on Desktop folder names. Do not copy entire folders without review.

| Topic | Candidate folders |
| --- | --- |
| Causal and event evaluation | 不朽杯弹窗PSM实验; 因果推断实操; 游戏主播跨播带来的影响; 莫拉塔合作效果分析 |
| Video-channel DAU and recurring reports | 月报_虎牙外部生态DAU; 月报_附录; 周报_附录; 周报监控模型 |
| Streamer value, growth, and anti-fraud | 反挖; 快手王者荣耀主播反挖数据; 无畏契约份额增长; 王者主播潜力分析; 斗鱼潜力主播挖掘 |
| User behavior and retention | 用户画像分析; 各类留存率取数; 社区评估; 星秀兴趣指数分析; 兴趣指数 |
| AI workshop | AI工坊专题; AI工具说明; AI直播间信息; AI直播间监控UID |
| Game and event topics | 世界杯专题; 斯诺克专题; 王者下跌和吕德华离开影响; 主机游戏需求; 赛事总结 |

For each selected project, record purpose, population, metric definitions, time windows, known findings, open questions, and links to code and deliverables. Include important artifacts that support findings or follow-up work. Detailed user-level Excel remains excluded under the original requirement unless the user explicitly changes that boundary.

## ChatGPT Conversation History

Request an account data export if the account or workspace offers it, then review the conversations and project history. Keep a complete encrypted archive when useful. API-based conversations may be stored by the calling application or company system and may not appear in a ChatGPT account export.

## Credentials

Credentials are in scope for migration. Place required `.env` files and other credential-bearing configuration in a client-encrypted bundle; do not store plaintext in GitHub. Store the decryption key separately. Rotate credentials exposed in chat or plaintext instruction files before creating the encrypted bundle.

Chinese version: `migration-inventory.md`.
