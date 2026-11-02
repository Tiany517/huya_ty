# Bigdata MCP Migration Guide

This directory archives the portable client configuration, tool contract, operating rules, troubleshooting notes, and new-computer recovery steps for Huya's `bigdata` MCP. The goal is to let Codex on the new computer reconnect to the same authorized service without committing credentials, query results, or user-level data.

## GitHub path map

| GitHub path | Contents |
| --- | --- |
| `mcp/bigdata/README.md` / `README.en.md` | Chinese / English recovery and operating guide |
| `mcp/bigdata/config.example.toml` | Codex MCP client template; gateway and approval policy only, no credentials |
| `mcp/bigdata/tool-catalog.json` | The 11 currently exposed tools, arguments, and safety boundaries |
| `mcp/bigdata/smoke-test.sql` | Minimal Presto connectivity check for the new computer |
| `vault/migration-secrets.aesgcm` | Encrypted data-platform account/API credentials; no plaintext in Git |

## Migration boundary

Archived:

1. The `mcp_servers.bigdata` client configuration shape used by Codex.
2. The current tool catalog, purposes, key arguments, and default safety policy.
3. Presto/Spark selection, one-statement execution, polling, result download, and partition-check rules.
4. Common authentication, gateway, and query failures.
5. Encrypted credential storage and recovery paths.

Not archived:

1. Huya's server-side MCP source or binary. The client connects to a company-managed remote gateway; no standalone server implementation exists on this machine.
2. `app_id`, `passport`, `X-BIGDATA-SECRET`, cookies, request signatures, or any live credential value.
3. User-level rows returned by MCP, signed download URLs, or large result files.

The repository can therefore help a new Codex reconfigure the MCP, but the remote tools still require company network access and valid credentials.

## New-computer setup

1. Install and sign in to Codex on the new computer, then confirm access to the company network or required VPN.
2. Open `config.example.toml` and merge its `[mcp_servers.bigdata]` and `[mcp_servers.bigdata.tools.*]` sections into `%USERPROFILE%\.codex\config.toml`. Do not overwrite an existing configuration wholesale.
3. Restart Codex and confirm that `mcp__bigdata__execute_sql`, `mcp__bigdata__get_latest_partitions`, and `mcp__bigdata__get_table_ddl` appear in the tool list.
4. Move the external `huya_ty-env-files.key` securely, decrypt `vault/migration-secrets.aesgcm`, and read `credentials/bigdata-platform.txt`.
5. Put `app_id` / `passport` into the Codex or organizational credential store, or into the gateway-required headers. Never write the values into this repository, SQL, chat, shell history, or a configuration template.
6. Run the `SELECT 1` check in `smoke-test.sql`; then run a read-only metadata or partition check.
7. Before formal extraction, recheck environment, permissions, and the latest partitions, then download only the required result.

## Environment and engines

- Default environment: `domestic`. Use `overseas` only for the explicitly relevant company-facing environment.
- Default engine: Presto. Rewrite for Spark only after a Presto syntax, capacity, or capability failure. Do not silently switch engines after a timeout and mix incomparable results.
- Submit one statement per `execute_sql` request. Run multiple validation statements separately; never combine `create table`, `insert overwrite`, and `select` in one request.
- `wait_for_result` and `timeout` control client waiting and polling, not the underlying job. Record `rid` and poll with `get_query_status` for long jobs.
- Prefer `get_query_result`, whose default limit is 500 MB. Use `download_query_result_raw` only after checking size, memory, storage, and authorization.
- For local files, prefer short-lived signed downloads with authentication headers. Never persist signed URLs or authentication headers in SQL or Git.

## Tool contract

| Tool | Purpose | Boundary |
| --- | --- | --- |
| `execute_sql` | Run Presto/Spark SQL | Defaults to waiting; record `rid` for long jobs and do not submit duplicates |
| `get_query_status` | Poll state and progress by `rid` | Not a result download; continue polling when not ready |
| `get_query_result` | Size-checked result download, default 500 MB | Preferred download path |
| `download_query_result_raw` | Raw download without size checking | Only for a known size with explicit authorization; memory and timeout risk |
| `get_download_url` | Generate a short-lived authenticated download URL | Never retain the URL or authentication headers |
| `get_latest_partitions` | Inspect the latest table partitions | Required before “from date X onward” extraction or an equivalent check |
| `get_table_ddl` | Inspect DDL and catalog identity | Use the returned `full_name`; do not guess a catalog |
| `get_table_metadata` | Inspect column metadata | Semantic evidence only; verify units with business rules and samples |
| `query_data_lineage` | Find upstream/downstream Lighthouse tasks | Relationship evidence only, not definition proof |
| `get_task_detail` | Inspect a Lighthouse task and dependencies | Read-only; do not modify production jobs |
| `query_event_data` | Inspect Doris event definitions | Confirm product/event scope; this is not the user-level behavior table itself |

See `tool-catalog.json` for the complete argument contract.

## Standard extraction workflow

1. Define the business question, source table, period, grain, unique key, numerator, and denominator.
2. Verify fields and catalog names with `get_table_ddl` / `get_table_metadata`.
3. Verify actual coverage with `get_latest_partitions`; never treat a missing partition as user non-retention.
4. Run the smallest read-only probe in Presto; rewrite for Spark only when needed.
5. Record `rid`, engine, environment, actual range, elapsed time, result rows, and output path.
6. Reconcile a small aggregate before downloading the full result. For user-level data, reconfirm purpose and cleanup policy.
7. Reconcile report, SQL, staging/target tables, CSV, and XLSX. Mark every unexecuted check as not run.

## Common failures

| Symptom | Meaning | Response |
| --- | --- | --- |
| `Missing credentials` | Authentication headers or runtime credentials are absent | Fix secure credential injection; do not guess or send secrets in chat |
| `status=1003` / header validation failure | Missing, swapped, or stale `app_id` / `passport` | Correct the credential mapping and reauthenticate |
| `status=1006` | Network, gateway, or transport failure | Check VPN/internal network and gateway status; it does not mean the partition is empty |
| `SHOW PARTITIONS` unsupported by Presto | Engine syntax difference | Use a supported query or `get_latest_partitions` |
| Query succeeded but result is not ready | Asynchronous job still running | Keep `rid` and poll `get_query_status` |
| Result exceeds 500 MB | Default safety threshold | Aggregate, reduce columns, or use a separately authorized controlled download |

## Security

- The MCP configuration may contain the gateway URL and approval policy; it must not contain `app_id`, `passport`, secrets, cookies, or signed URLs.
- Treat returned authentication headers as secrets, not ordinary data.
- Confirm target table, partition, impact, and recovery before any write or overwrite.
- Prefer anonymous aggregates after user-level analysis. Retain details only on explicit request and document the cleanup/retention period.
- If the organization classifies the gateway address as sensitive, replace that line with an internal secret-manager reference. This private repository currently retains the connection template at the user's explicit request.

Chinese version: `README.md`.
