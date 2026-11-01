# Migration Inventory

Status: as of 2026-11-02, the migration repository has been committed and pushed to the private GitHub repository. Source files remain in place; only reviewed notes, SQL, skills, project scripts, and anonymized results have been organized in the repository. Remaining candidates below still require individual review and are not considered migrated based on folder names alone.

## Working Rules

| Candidate | Current source | Status |
| --- | --- | --- |
| Data-analysis working rules | `instructions/AGENTS.md` is based on the attached text; its credential-bearing line was replaced with a secure-storage instruction | Included; checked against the attachment in this conversation |
| Desktop AGENTS version | `Desktop/agents_md/AGENTS.md` | Differs from the attachment; retained for comparison |
| Codex and Claude rules | `.codex/AGENTS.md`, `.claude/AGENTS.md` | Compare before merging |

The attachment matches the AGENTS content shared in this conversation. Compared with the Desktop version, it adds two rules; one contained a plaintext API credential and has been replaced in the migration copy with a secure-storage instruction.

## SQL

The SQL source contains 240 `.sql` files and 2 SQL-formatted `.txt` files, copied under their original names into `sql/source/`. It also contains 54 CSV files, 22 Excel files, and 25 Python scripts. One FPS project includes seven analysis scripts, and the HuShi/HuXiao ACU-threshold project includes one reusable script. Other result data, scripts, and `content_categories_full.txt` remain queued for project review. Review important results individually; detailed user-level Excel remains out under the original boundary.

The high-priority retention index is at `sql/topics/retention-analytics/`. The recommended external pipeline runs `zty_jingpin_user_activity_di_日跑调度.sql` into `zty_jingpin_用户活动月度流水留存_调度版_1030_v1.sql`, covering Douyu, Bilibili, and Douyin; the current Huya script covers Star Show totals and subcategories. D7/D14/D30 mean natural dates T+6/T+13/T+29. The triple-counted Huya common-cohort denominator is now isolated with a corrected CTE, target-table validation SQL, and anonymous January 2025 through October 2026 overall comparisons under the remediation directory and artifacts. The existing 132-row target table has not been refreshed; inferred corrected rates divide the stored base by three. Before a formal refresh on the new computer, validate source coverage for T+6/T+13/T+29 and recheck Douyin danmu availability.

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

### First-Pass File Inventory (Metadata Only)

Counts, extensions, and modification dates for the candidates below come from filesystem metadata. The ten reviews listed above are complete; all other candidates have not been reviewed or copied yet.

Reviewed and pushed projects: `projects/valorant-5937-p50-live-time/`, `projects/fps-anchor-cleaning/`, `projects/monthly-external-ecosystem-dau/`, `projects/valorant-fps-cross-broadcast/`, `projects/valorant-watchtime-contribution-knee/`, `projects/valorant-yuezi-event-costream/`, `projects/valorant-ob-costream-scenario/`, `projects/huya-douyin-valorant-acu-threshold/`, `projects/valorant-big-pot-share-scenario/`, and `projects/valorant-anti-fraud-event-review/`. The FPS project includes seven analysis scripts and an anonymized quantile summary CSV; streamer-level attachments were excluded. Its 2.6489% model ratio is documented as a source-workbook value with a category-scope mismatch, not as a share conclusion.

The external ecosystem DAU report is documented at `projects/monthly-external-ecosystem-dau/`: its SQL and anonymized monthly platform aggregates from 2025-07 through 2026-05-18 are retained. Two source workbooks containing streamer IDs, nicknames, contracts, or revenue were excluded.

The OB co-streaming scenario is documented at `projects/valorant-ob-costream-scenario/` with formulas and anonymized aggregates only. The workbook's 21% success probability differs from its “1 in 5” note, and a listed 11.47-minute watch-time delta is not used in the increment formula. Both are disclosed as model limitations; the 2.6944% scenario is not presented as realized or causal share growth. The source workbook with streamer-level details was excluded.

The HuShi/HuXiao monthly ACU threshold review is documented at `projects/huya-douyin-valorant-acu-threshold/`, with anonymized monthly counts, pool sizes, maxima, and the generating script. Streamer lists and the identity-bearing workbook were excluded. The `valid_acu` dictionary is missing and the October 2026 cutoff is unknown; both are documented on the project page.

The Big Pot watch-time share estimate is documented at `projects/valorant-big-pot-share-scenario/`, with anonymized internal/external aggregates for two scenarios. The primary scenario is about 5.4386% and the alternative about 2.5577%; the alternative omits one internal record, the historical source and industry-baseline periods differ, and the denominator category is unspecified. Treat these as unvalidated model scenarios. The identity-bearing workbook was excluded.

The anti-fraud review is documented at `projects/valorant-anti-fraud-event-review/`, with anonymized summaries for all events, first-stream 7/14/30-day windows, 30-day strata, and the workbook scenarios. The workbook has at least three inconsistent event universes; the 40% success threshold and target counts are assumptions. Streamer IDs, nicknames, and event-level details were excluded.

The FPS cross-broadcast final compact workflow is documented at `projects/valorant-fps-cross-broadcast/`, with the event-table SQL, tier success-rate query, and anonymized validation baseline. Event-level streamer details were not migrated; success rates are descriptive event statistics, not causal effects.

The watch-time contribution knee review is documented at `projects/valorant-watchtime-contribution-knee/`, with actual-watch-time monthly knees, Top-N coverage, monthly 0.2% qualification aggregates, and core scripts. Raw/cleaned data, streamer-month shares, and workbooks with streamer identities were excluded; verify upstream field definitions before rerunning on the new computer.

The single-streamer Huya-affiliated Douyin co-streaming case is documented in de-identified form at `projects/valorant-yuezi-event-costream/`, with event/non-event window and monthly aggregates plus analysis scripts. Nickname, platform ID, daily detail, and identity-bearing workbook were excluded. Post-event ACU retention is explicitly not user retention, and data ends on 2026-10-11.

| Priority candidate | Current size and latest modification | Review focus |
| --- | --- | --- |
| 无畏契约份额增长 | 201 files; latest 2026-10-29; 90 Python, 41 Excel, 21 CSV | The 5937, OB co-streaming, HuShi/HuXiao ACU-threshold, Big Pot, and anti-fraud subprojects are documented separately; non-Douyin discovery and others still need review |
| FPS主播清洗_20261023 | 76 files; latest 2026-10-23; 6 Excel, 28 CSV, 6 NDJSON | Select estimate outputs and scripts; distinguish detailed data from inspection artifacts |
| 周报监控模型 | 55 files; latest 2026-10-23; 8 SQL, 1 Python, 25 Excel, 21 CSV; largest workbook about 289 MB | Identify templates, data, and reusable monitoring logic; do not push the largest workbook wholesale |
| AI工坊专题 | 403 files; latest 2026-09-24; includes Python, Excel, CSV, TSV, and PKL | Data-heavy; first identify core project notes, scripts, and aggregate outputs |
| 不朽杯弹窗PSM实验 | 195 files; latest 2026-06-17; includes reports, Excel, CSV, Python, and images | Review the final report and key aggregate tables; exclude user-level details and intermediate charts |
| 反挖 | 33 files; includes 8 notebooks and 8 Python files; contains an approximately 169 MB RAR and 21 MB TAR | Archive contents are unknown; identify purpose and necessity before upload |
| 用户画像分析 | 151 files; latest 2026-05-29; includes 3 SQL and 10 CSV files; one CSV is about 36 MB | Evaluate SQL and conclusion materials first; keep user-profile detail CSV out for now |
| 月报_虎牙外部生态DAU | 3 files: 1 SQL and 2 template workbooks | Small footprint; review templates for inclusion |
| Documents/ChatGPT/异动归因 | 12 Python scripts and outputs; includes summary workbooks and a workbook named as detail; Git working tree has no commit history | Review recent Video Channel DAU attribution; identify summary versus detailed workbooks individually |

The `douyin-playwright` skill snapshot also contains Top 10 video-analysis workbooks, scripts, images, and temporary JSON ignored by the source `.gitignore`. They are not in the repository and will be reviewed separately as project evidence.

## Remaining Work

- Continue reviewing non-Douyin streamer discovery and other distinct subprojects under the Valorant share-growth folder, then move to other priority candidates.
- Other projects in this inventory remain pending review, not archived. For each completed review, update this inventory and the root path map, inspect the full diff, and push the changes.
- A raw ChatGPT export has not been archived. Confirm whether the company API account offers an account-level export; API work records may not be part of a ChatGPT web-account export.

For each selected project, record purpose, population, metric definitions, time windows, known findings, open questions, and links to code and deliverables. Include important artifacts that support findings or follow-up work. Detailed user-level Excel remains excluded under the original requirement unless the user explicitly changes that boundary.

## ChatGPT Conversation History

Request an account data export if the account or workspace offers it, then review the conversations and project history. Keep a complete encrypted archive when useful. API-based conversations may be stored by the calling application or company system and may not appear in a ChatGPT account export.

## Credentials

Four actual `.env` files found under the user profile are encrypted in `vault/env-files.aesgcm`. `.env.example` files, templates, and shortcuts are not duplicated in the bundle. The key is stored outside the repository in the local Documents folder and must be transferred separately by the current Windows user. GitHub contains no plaintext credentials. Rotate credentials exposed in chat or plaintext instruction files before continuing to reuse them.

Chinese version: `migration-inventory.md`.
