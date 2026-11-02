# Skills Archive

This directory preserves local skill snapshots by installation source:

| Source directory | Skill folders | Archived files | Notes |
| --- | ---: | ---: | --- |
| `codex/` | 56 | 503 tracked | Codex user and system-managed skills |
| `shared-agent/` | 45 | 82 | Shared agent skills |
| `claude/` | 54 | 503 tracked | Claude skills |
| `plugins/hyperframes/0.1.2/` | 5 | 69 | Complete offline snapshot of the HyperFrames v0.1.2 Codex plugin containing `gsap`, `hyperframes`, `hyperframes-cli`, `hyperframes-registry`, and `website-to-hyperframes` |

The local snapshot contains 1,182 copied source files; 1,088 skill files are tracked in this repository, plus these two guide files. Same-named copies are retained under each source for provenance. `.git`, caches, virtual environments, dependency folders, bytecode, and real `.env` files were excluded; `.env.example` files may be retained. Another 94 files are excluded by source `.gitignore` files. Four public Top 10 video-analysis XLSX files from `douyin-playwright` were reviewed and moved into `projects/douyin-playwright-video-analysis/`; `.superpowers/sdd` reports/diffs, individualized generators, screenshots, and temporary JSON remain excluded. Test tokens and environment-variable examples remain unchanged; no real `.env` files or common token formats were found.

`plugins/` is an additional Codex-plugin archive and is not mixed into the file counts of the three user/agent skill source directories. HyperFrames comes from <https://github.com/heygen-com/hyperframes>; the plugin manifest declares version `0.1.2` and Apache-2.0. Prefer reinstalling through the Codex plugin interface on the new computer and use the repository snapshot for offline inspection and recovery. Chinese version: `README.md`.
