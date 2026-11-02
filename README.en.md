# ChatGPT / Codex Migration Kit

This repository hands reusable work materials over to a new computer: working rules, skills, SQL references, project context, and selected project evidence. It does not replace ChatGPT account history or machine-local configuration.

## GitHub Repository Map

| Repository path | Contents |
| --- | --- |
| `README.md` / `README.en.md` | Chinese / English guide and new-computer bootstrap |
| `instructions/AGENTS.md` / `instructions/AGENTS.en.md` | Chinese / English data-analysis working rules; secret values go in an encrypted vault |
| `instructions/sql-validation-workflow.md` / `.en.md` | General seven-stage SQL proof chain, static review, risk profile, nine validation dimensions, delivery reconciliation, and recurrence controls |
| `instructions/templates/sql-validation-record.md` / `.en.md` | Bilingual delivery card required for every formal SQL task; records the contract, risk profile, eight-gate evidence, independent recomputation, delivery reconciliation, and completion status |
| `skills/README.md`, `skills/<source>/<skill-name>/` | Skills archive guide and full snapshots by installation source |
| `sql/README.md`, `sql/source/<file>` | SQL archive guide and source files under their original names; topic indexes can be added later |
| `sql/topics/retention-analytics/` | Retention SQL index, dependencies, definitions, versions, and known defects for external Douyu/Bilibili/Douyin and Huya Star Show danmu/gift behavior |
| `sql/topics/retention-analytics/remediation/`, `sql/topics/retention-analytics/artifacts/` | Huya Star Show denominator fix and validation SQL, plus anonymous January 2025 through October 2026 overall comparisons |
| `projects/<project-slug>/README.md` / `README.en.md` | Project purpose, scope, metric definitions, findings, limitations, and sources; reviewed projects are listed in the project paths below |
| `projects/<project-slug>/scripts/` | Reproducible project scripts; the FPS project includes 7 cleaning and analysis scripts |
| `projects/<project-slug>/artifacts/` | Important result files; the FPS project includes an anonymized live-time quantile CSV |
| `projects/monthly-external-ecosystem-dau/` | External ecosystem DAU workflow, SQL definitions, and anonymized monthly aggregates |
| `projects/monthly-report-appendix/` | Monthly-report appendix: daily and monthly video-channel stream-type DAU, external-platform DAU, Douyin MCN category DAU, APP retention, and game exclusivity; includes anonymous artifacts, four SQL files, hashes, and known defects |
| `projects/weekly-ecosystem-monitoring/` | Weekly ecosystem monitoring: daily category and streamer SQL, six anonymized snapshots, platform DAU, template structure, and reproducible validation |
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
| `projects/causal-inference-handbook/` | PSM/SCM teaching handbook: five source editions, 74 editable code blocks, eleven method risks, a production checklist, source hashes, and bilingual validation reports |
| `archive/chatgpt-export/` | Reviewed ChatGPT export archive, encrypted when retained |
| `mcp/bigdata/README.md` / `.en.md`, `config.example.toml`, `tool-catalog.json` | Bigdata MCP gateway template, 11-tool contract, Presto/Spark/download rules, and troubleshooting; no account or API secret |
| `vault/migration-secrets.aesgcm` | AES-256-GCM encrypted `.env` and data-platform credential bundle; decryption key stored separately |
| `vault/env-files.aesgcm` | Legacy `.env` bundle retained as a historical copy; use `migration-secrets.aesgcm` on the new computer |
| `inventory/migration-inventory.md` / `.en.md` | Chinese / English source inventory and review queue; explicitly skipped projects are recorded here with no project GitHub path |
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
5. Recreate local paths using `local-source-map.md`; transfer `huya_ty-env-files.key` from outside the repository to the new computer through a secure channel, then use `vault/decrypt-env-files.mjs` to decrypt `vault/migration-secrets.aesgcm` into a staging directory and restore files individually.
6. Read project context and result artifacts under `projects/` before continuing work.
7. Reconnect approved data services and validate access before running saved SQL.

## Syncing Future Work

After each useful work retrospective, or when reusable SQL is added or revised, Codex should update the matching Chinese and English notes and automatically commit and push them to this private repository. Before each push, inspect the full diff and confirm the scope contains no plaintext credentials, unreviewed data, or unrelated changes from other projects. See `instructions/AGENTS.en.md` for the full rule.

Chinese version: `README.md`.
