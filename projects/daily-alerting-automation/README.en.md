# Daily Data Alerting and Automated Reporting

This project documents a historical operational automation suite that pulled results from HDFS/Hive temporary tables, evaluated business thresholds, rendered HTML tables, and delivered daily, weekly, and monthly alerts through corporate email or a WeCom bot. The migration objective is to preserve the business context and reusable methods, not the original daily outputs, plaintext accounts, passwords, webhooks, or internal recipient routes.

## Business Context

The suite automated repeated daily monitoring and routed anomalies to people. It covered direct drivers of APP DAU, head-streamer supply, acquisition/reactivation versus churn, existing-user retention, streamer-supply expansion, weekly category KPI progress, Douyu/Kuaishou dual-broadcast activity, and operating data for the game “奶块”.

The source scripts span 2024-2025 and the archive also contains dated HDFS exports, screenshots, and email/HTML output. They document the definitions and thresholds used at the time but do not make a historical alert a current business conclusion.

## GitHub Path Map

| Repository path | Contents |
| --- | --- |
| `projects/daily-alerting-automation/README.md` | Chinese background, modules, definitions, pipeline, and risks |
| `projects/daily-alerting-automation/README.en.md` | Standalone English version |
| `vault/migration-secrets-v2.aesgcm` | Encrypted related mailbox, platform webhook, HDFS identity, and recipient routing credentials |
| `archive/codex-work-history/codex-work-history-20261102.aesgcm` | Encrypted digest of related local work threads |

`vault/` is cross-project migration infrastructure at the repository root. It is not part of this project and should not be copied into the project directory.

## Monitoring Modules

| Module | Business question | Core output |
| --- | --- | --- |
| APP DAU driver report | Which controllable factors explain today's DAU change? | Event DAU, head-streamer live rate, acquisition/reactivation versus churn, existing-user retention, streamer-supply net change, month-end long-term decline list |
| Head-streamer alert | Are critical streamers broadcasting effectively and consistently? | Weighted live rate, non-compliant streamers, consecutive missed days, attributed DAU |
| Weekly category KPI progress | Is DAU growth on pace for the annual target? | Group/category targets, weekly and monthly DAU, completion progress, time progress |
| Douyu/Kuaishou dual-broadcast report | How large is cross-platform dual broadcasting and its platform DAU contribution? | Dual-broadcast streamer count, Huya APP DAU, acquisition/reactivation, streamer detail |
| “奶块” operating report | Are game DAU and payment performance abnormal? | Daily DAU, paying users, payment amount; month-end MAU/payer averages and monthly revenue |

## Definitions and Thresholds

### Head-Streamer Live Rate

- Universe: streamers whose seven-day median of longest-watch-time attributed DAU exceeded 10,000, deduplicated by month.
- Effective live day: more than two live hours, excluding replay channels and rooms longer than 18 hours.
- Weighted live rate: weights are linear in attributed user scale so missing major streamers is not hidden by a large count of small streamers.
- Alert threshold: weighted live rate below 85%.

### Acquisition, Reactivation, and Churn

The contribution of new and reactivated users is the average daily DAU over T through T+6 for users acquired or reactivated on day T, where reactivation means return after 30 inactive days. Churn loss uses users active between T-59 and T-30 but inactive in the latest 30 days, measured over their seven days before churn. Overlap users are removed. A negative net contribution triggers the alert.

### Existing-User Retention

The metric is seven-day retention among existing users after excluding event and major-streamer effects. The baseline is the daily average over the preceding two months. Because a seven-day retention observation requires T+6, the reference months update on the sixth day of each month. A decline greater than 1.3 percentage points triggers the alert.

### Streamer-Supply Expansion

New streamers are live for the first time on that day; returning streamers return after at least 180 silent days; churned streamers were live between T-59 and T-30 and have not been live in the latest 30 days. Streamers are grouped by their longest live category into PC games, mobile games, entertainment, licensed content, and other. Platform relationship indices convert users into DAU. Streamers contributing more than 10,000 platform DAU and signed million-level streamers or teams are excluded. A negative net contribution triggers the alert.

### Head-Streamer Long-Term Decline

The candidate universe is the watch-time Top 50 over the prior three months, excluding events and replay channels. “Extra decline” is streamer DAU decline minus the decline of the streamer's category. An extra decline above 15% triggers an alert. The threshold came from the 80th percentile of historical head-streamer volatility. A streamer that remains below the prior alert can continue to be flagged for up to three months.

### Weekly Category KPI Progress

Completion is:

`(current weekly or monthly category DAU - baseline category DAU) / (target category DAU - baseline category DAU) × 100%`

The baseline is 2025 Q1 and the target is the level required by December 2025. Time progress runs from 2025-04-01 through 2025-12-31, a total of 275 days. Completion at or above time progress is considered on track. The first week of each month reports the prior month's DAU and completion.

## Technical Pipeline

1. Read the business date from an environment variable or command-line argument.
2. Pull Hive temporary-table partitions from HDFS into a run-specific directory.
3. Read TSV parts into pandas, concatenate, and rename fields.
4. Evaluate thresholds and build metric tables, calendar heatmaps, or month-end sections.
5. Render HTML using Microsoft YaHei fonts.
6. Send through corporate SMTP_SSL or a WeCom bot webhook.
7. Remove the run-specific export directory.

## Reuse Guidance

- Read credentials from environment variables or a secret manager; never restore the historical hard-coded accounts, passwords, webhooks, or recipient lists.
- Parameterize the HDFS identity, table names, and partition checks. Validate date, row count, partition coverage, and metric direction before sending.
- Move thresholds, definitions, and notification routes into versioned configuration.
- Independently recompute acquisition, reactivation, churn, event, and major-streamer exclusions; never treat a missing partition as zero.
- Use idempotency keys, and log input partitions, query duration, delivery state, and failures for every run.

## Known Limitations

- The scripts depend on internal HDFS paths, Hive temporary tables, and historical accounts and cannot run directly in a new environment.
- Historical code contains hard-coded credentials, fixed recipients, and copied versions without a unified test or configuration system.
- Many metrics depend on upstream temporary tables; this repository has no build SQL, field dictionary, or partition lineage.
- No historical date was rerun during migration. The preserved method is inspectable, but current reproducibility is not established.

## Excluded Material

- The original `mailall.tar.gz`, approximately 11,916 historical files, and dated exports.
- Plaintext SMTP accounts/passwords, WeCom webhooks, HDFS identities, internal recipient routes, and run screenshots.
- Hive/Spark upstream source and table-build SQL. Relevant credentials remain only in the encrypted vault.

Chinese version: `README.md`.
