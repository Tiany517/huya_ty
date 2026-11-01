# ChatGPT / Codex Migration Kit

This repository hands reusable work materials over to a new computer: working rules, skills, SQL references, project context, and selected project evidence. It does not replace ChatGPT account history or machine-local configuration.

## GitHub Repository Map

| Repository path | Contents |
| --- | --- |
| `README.md` / `README.en.md` | Chinese / English guide and new-computer bootstrap |
| `instructions/AGENTS.md` / `instructions/AGENTS.en.md` | Chinese / English data-analysis working rules; secret values go in an encrypted vault |
| `skills/<skill-name>/` | Preserved skill snapshot with its references and required assets |
| `sql/<topic>/<file>.sql` | Reusable SQL organized by business topic |
| `projects/<project-slug>/README.md` / `README.en.md` | Project purpose, scope, metric definitions, findings, limitations, and sources |
| `projects/<project-slug>/scripts/` | Reproducible project scripts |
| `projects/<project-slug>/artifacts/` | Important result files that support understanding or continuing the project |
| `archive/chatgpt-export/` | Reviewed ChatGPT export archive, encrypted when retained |
| `vault/env-files.age` | Client-encrypted `.env` bundle; decryption key stored separately |
| `inventory/migration-inventory.md` / `.en.md` | Chinese / English source inventory and review queue |
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
4. Recreate local paths using `local-source-map.md`; restore the encrypted credential bundle using its separately stored decryption key.
5. Read project context and result artifacts under `projects/` before continuing work.
6. Reconnect approved data services and validate access before running saved SQL.

## Syncing Future Work

After each useful work retrospective, or when reusable SQL is added or revised, Codex should update the matching Chinese and English notes and automatically commit and push them to this private repository. Before each push, inspect the full diff and confirm the scope contains no plaintext credentials, unreviewed data, or unrelated changes from other projects. See `instructions/AGENTS.en.md` for the full rule.

中文版本见 `README.md`。
