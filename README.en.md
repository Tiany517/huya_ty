# ChatGPT / Codex Migration Kit

This repository hands reusable work materials over to a new computer: working rules, skills, SQL references, project context, and selected project evidence. It does not replace ChatGPT account history or machine-local configuration.

## Top-Level Directory Responsibilities

| Top-level path | Responsibility |
| --- | --- |
| `projects/README.md` / `README.en.md` | Bilingual index of every reviewed project and its project path |
| `projects/` | Project context, methods, SQL/scripts, anonymous results, validation, and project-level maps |
| `vault/` | Encrypted bundles for cross-project migration credentials. It is parallel to `projects/`, not an attachment to one project, and must not be nested under `projects/` |
| `archive/` | Encrypted local ChatGPT/Codex work-history archive |
| `instructions/` | AGENTS rules, SQL validation workflow, and templates |
| `skills/` | Source-aware skill snapshots and restore guidance |
| `sql/` | Cross-project SQL index, topics, and remediations |
| `mcp/` | Bigdata MCP template, tool contract, and recovery guidance |
| `inventory/` | Source inventory, completion status, skipped items, and review queue |

## GitHub Repository Map

| Repository path | Contents |
| --- | --- |
| `README.md` / `README.en.md` | Chinese / English guide and new-computer bootstrap |
| `instructions/AGENTS.md` / `instructions/AGENTS.en.md` | Chinese / English data-analysis working rules; secret values go in an encrypted vault |
| `instructions/sql-validation-workflow.md` / `.en.md` | General seven-stage SQL proof chain, static review, risk profile, nine validation dimensions, delivery reconciliation, and recurrence controls |
| `instructions/templates/sql-validation-record.md` / `.en.md` | Bilingual delivery card required for every formal SQL task; records the contract, risk profile, eight-gate evidence, independent recomputation, delivery reconciliation, and completion status |
| `skills/README.md`, `skills/<source>/<skill-name>/` | Skills archive guide and full snapshots by installation source |
| `skills/plugins/hyperframes/0.1.2/` | Offline snapshot of the HyperFrames v0.1.2 Codex plugin and its five presentation/video skills; prefer reinstalling the plugin on the new computer |
| `sql/README.md`, `sql/source/<file>` | SQL archive guide and source files under their original names; topic indexes can be added later |
| `sql/reference/common-anchor-and-game-id-maps.md` / `.en.md` | Bilingual SQL reference maps for common anchor IDs, assigned business categories, and `game_id` values; not a replacement for platform dimensions |
| `sql/topics/retention-analytics/` | Retention SQL index, dependencies, definitions, versions, and known defects for external Douyu/Bilibili/Douyin and Huya Star Show danmu/gift behavior |
| `sql/topics/retention-analytics/remediation/`, `sql/topics/retention-analytics/artifacts/` | Huya Star Show denominator fix and validation SQL, plus anonymous January 2025 through October 2026 overall comparisons |
| `projects/README.md` / `README.en.md` | Bilingual index of all projects; use it first to locate a project, then open that project's README |
| `projects/<project-slug>/README.md` / `README.en.md` | Project purpose, scope, metric definitions, findings, limitations, and sources; reviewed projects are listed in the project paths below |
| `projects/<project-slug>/scripts/` | Reproducible project scripts; the FPS project includes 7 cleaning and analysis scripts |
| `projects/<project-slug>/artifacts/` | Important result files; the FPS project includes an anonymized live-time quantile CSV |
| `projects/monthly-external-ecosystem-dau/` | External ecosystem DAU workflow, SQL definitions, and anonymized monthly aggregates |
| `projects/monthly-report-appendix/` | Monthly-report appendix: daily and monthly video-channel stream-type DAU, external-platform DAU, Douyin MCN category DAU, APP retention, and game exclusivity; includes anonymous artifacts, four SQL files, hashes, and known defects |
| `projects/douyin-playwright-video-analysis/` | Four public video-analysis XLSX examples from the `douyin-playwright` skill, 40 Top 10 records, bilingual indexes, source hashes, and structural validation |
| `projects/weekly-ecosystem-monitoring/` | Weekly ecosystem monitoring and interactive dashboard: reproducible build package, metric workbook, refresh skill, production SQL, historical anonymized snapshots, and reproducible validation |
| `projects/wechat-channel-dau-attribution/` | Two-week WeChat Channel audience attribution: complete de-identified anchor-day basis, corrected decomposition, activity/content/duration splits, anonymous workbook, path map, and 40 checks |
| `projects/ai-workshop-commercialization/` | AI Workshop commercialization: PSM7/PSM8, DID, paid retention, version conversion, manual gift tagging, anonymous category/ACU summaries, final business page, and reproducible validation |
| `projects/buxiucup-popup-psm/` | Three separate Buxiucup PSM/DID reviews: check-in campaign, same-day DOTA2 exposure, and April-interest exposure; final reports, anonymous results, core SQL/scripts, defect review, and automated validation |
| `projects/valorant-fps-cross-broadcast/` | FPS cross-broadcast event SQL, ACU-tier success-rate query, and anonymized validation baseline |
| `projects/valorant-watchtime-contribution-knee/` | Anonymized actual watch-time knee, Top-N coverage, and monthly candidate-screen results with scripts |
| `projects/valorant-yuezi-event-costream/` | De-identified event co-streaming case, window aggregates, and analysis scripts |
| `projects/valorant-ob-costream-scenario/` | OB co-streaming scenario formula review and anonymized model summary with assumptions |
| `projects/huya-douyin-valorant-acu-threshold/` | Anonymized monthly results and review of HuShi/HuXiao streamer ACU thresholds |
| `projects/valorant-5937-p50-live-time/`, `projects/fps-anchor-cleaning/` | 5937 P50 valid-month live-time estimate, and FPS streamer live-time cleaning and quantile review |
| `projects/valorant-big-pot-share-scenario/` | Big Pot watch-time share scenarios, with anonymized aggregates and period, denominator, and coverage limitations |
| `projects/valorant-anti-fraud-event-review/` | Anonymized anti-fraud ACU, watch-share, and first-stream windows, with event-universe limitations |
| `projects/non-douyin-valorant-streamer-discovery/` | Non-Douyin Bilibili/Douyu/Kuaishou Valorant head candidates, monthly benchmarks, team-exclusion sensitivity, and anonymized results |
| `projects/valorant-streamer-potential-analysis/` | Valorant streamer-potential review: Huya internal interaction screen, Douyin v1/v2 sustained-leader comparison, September 2026 external talent pool, and anonymized validation evidence |
| `projects/external-streamer-reverse-poaching/` | Reverse-poaching heuristic review: Douyu/Bilibili historical predictions, Douyin/Kuaishou model functions, anonymous platform/category summaries, version drift, and known model defects |
| `projects/kuaishou-honor-of-kings-reverse-poaching/` | Kuaishou Honor of Kings reverse-poaching screen: six-workbook version chain, V1/V2 raw coverage, final V2-15 rule, Huya waist benchmark, anonymous artifacts, and 26 checks |
| `projects/user-profile-analysis/` | User-profile TGI and KMeans review: device, snooker acquisition, World Championship, and 10-minute-viewer cohorts; includes three SQL files, four historical reports, anonymous TGI/cluster artifacts, source hashes, and 49 checks |
| `projects/xingxiu-interest-index/` | January–July 2026 Xingxiu interest-index review: monthly DAU/interest, streamer status, July DAU deciles, eleven hypothesis groups, bilingual anonymous outputs, and 34 checks |
| `projects/molata-cooperation-acu-review/` | Six-anchor cooperation ACU review: four-window anonymous daily series, group growth, platform benchmarks, 13 reconciliation failures, bilingual workbooks, and 21 checks |
| `projects/ai-live-room-operations/` | AI live-room snapshots for July through September 2026: runtime and annotated SQL, anonymous anchor-category summaries, cross-month coverage, 13 SQL risks, bilingual workbooks, and 21 checks |
| `projects/ai-tool-guide/` | AI-tool selection and recovery: mav-slidecraft-skill for HTML slides, HyperFrames for HTML-driven motion video, five plugin skills, boundaries, and new-computer restore steps; 12 archive checks |
| `projects/event-summary-review/` | LPL, KPL, FISSURE, and BLAST event-summary review: DAU/acquisition/return for 16 event groups, YoY and phase comparisons, platform shares for 11 events, published and deduplicated views, a 20-row duplication audit, and the LPL final-sheet label mismatch; bilingual and 25 checks |
| `projects/snooker-event-review/` | Snooker and World Championship review: 89 final-delivery files, 61 SQL files, World Championship acquisition/tipping/video-live coverage, five event-to-World-Championship retention paths, video affinity, anonymous profiles, seven quality risks, and 36 checks; separate Chinese/English guides with a GitHub path map |
| `projects/causal-inference-handbook/` | PSM/SCM teaching handbook: five source editions, 74 editable code blocks, eleven method risks, a production checklist, source hashes, and bilingual validation reports |
| `projects/world-cup-content-review/` | World Cup review: acquisition/reactivation, balanced PSM, D7/D14 retention, profiles, search-interest migration, context, methods, historical estimates, and limitations; raw user detail and the 38 GB source tree were excluded |
| `projects/daily-alerting-automation/` | Alerting automation: modules, thresholds, pipeline, and reuse risks for head-streamer live rate, acquisition/reactivation versus churn, retention, supply, long-term decline, category KPI, dual broadcasting, and the 奶块 report; plaintext credentials remain only in the encrypted vault |
| `projects/console-game-revenue-review/` | Console-game request: January-May 2025 versus 2026 streamer-month revenue, payment structure, rankings, supply efficiency, anonymous monthly aggregates, V1/V2 formula defects, and lineage limits |
| `projects/honor-of-kings-streamer-departure-impact/` | Honor of Kings decline and streamer departure: daily/monthly attributed DAU, April-May overlap, retention/content migration, guild/head-streamer spillover, historical estimates, de-identified SQL, and reproducibility limits |
| `archive/codex-work-history/` | Codex local work-history and memory digest: 300 threads, 3,453 user requests, and 6,962 final/unspecified-phase replies; AES-256-GCM encrypted with exporter and validation record |
| `mcp/bigdata/README.md` / `.en.md`, `config.example.toml`, `tool-catalog.json` | Bigdata MCP gateway template, 11-tool contract, Presto/Spark/download rules, and troubleshooting; no account or API secret |
| `vault/migration-secrets-v2.aesgcm` | AES-256-GCM encrypted `.env`, data-platform credential, and legacy alert-script credential copy for this migration; decryption key stored separately |
| `vault/migration-secrets.aesgcm`, `vault/env-files.aesgcm` | Prior encrypted bundles retained as historical copies; use `migration-secrets-v2.aesgcm` on the new computer |
| `inventory/migration-inventory.md` / `.en.md` | Chinese / English source inventory, completion status, and review queue; migrated projects are located through `projects/README.md`, while explicitly skipped items retain their reason and exclusion boundary |
| `local-source-map.md` / `local-source-map.en.md` | Chinese / English local machine paths; kept locally and ignored by Git |

GitHub repository: <https://github.com/Tiany517/huya_ty>

These are repository-relative GitHub paths. For example, `instructions/AGENTS.md` maps to <https://github.com/Tiany517/huya_ty/blob/main/instructions/AGENTS.md>; directories map to `https://github.com/Tiany517/huya_ty/tree/main/<folder>`. Codex on the new computer can clone the repository and use this map to locate its contents.

## Inclusion Rules

- Required credentials will be placed in a client-encrypted bundle. Never commit plaintext keys, passwords, tokens, `.env` files, or credential-bearing configuration. Store the decryption key outside GitHub in a password manager or equivalent secure store.
- Preserve useful local and third-party skills, including required references and assets, and record their sources and versions. Deduplicate only after comparing contents.
- Include important result files that support project findings or follow-up work. Review each workbook or data file; detailed user-level Excel data stays out under the original requirement unless the user explicitly changes that boundary.
- Review raw ChatGPT exports and large generated outputs individually. Keep a complete encrypted archive when useful; leave rebuildable caches, dependencies, and temporary files outside the repository.
- Keep real credentials out of `.env.example`. Rotate credentials exposed in chat or plaintext instruction files before creating the encrypted bundle.

## New-Computer Bootstrap

1. Sign in to GitHub and clone this repository.
2. Read `instructions/AGENTS.en.md` and `inventory/migration-inventory.en.md` (Chinese versions are available at the corresponding paths without `.en`).
3. Restore skills from `skills/` and read their source and version notes.
4. Follow `mcp/bigdata/README.en.md` to merge the MCP configuration template, restart Codex, and confirm the bigdata tools appear.
5. Recreate local paths using `local-source-map.md`; transfer `huya_ty-env-files.key` from outside the repository to the new computer through a secure channel, then use `vault/decrypt-env-files.mjs` to decrypt `vault/migration-secrets-v2.aesgcm` into a staging directory and restore files individually.
6. Read `projects/README.md` to locate a project, then open its bilingual README, SQL/scripts, and anonymous result attachments.
7. Reconnect approved data services and validate access before running saved SQL.

## Syncing Future Work

After each useful work retrospective, or when reusable SQL is added or revised, Codex should update the matching Chinese and English notes and automatically commit and push them to this private repository. Before each push, inspect the full diff and confirm the scope contains no plaintext credentials, unreviewed data, or unrelated changes from other projects. See `instructions/AGENTS.en.md` for the full rule.

Chinese version: `README.md`.
