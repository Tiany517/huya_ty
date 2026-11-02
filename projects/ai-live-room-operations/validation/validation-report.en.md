# AI live-room snapshot review validation

Overall status: `incomplete`

| Check | Status | Evidence |
| --- | --- | --- |
| Source snapshots are readable with recognizable headers | PASS | Column counts: {'2026-08-07': 13, '2026-09-04': 11, '2026-10-09': 11} |
| The two 0807 CSV copies are identical | PASS | SHA-256 matches |
| Source manifest sizes and hashes match | PASS | 6 source files; mismatches=[] |
| Both SQL files are byte-identical to their sources | PASS | runtime=True; annotated=True |
| Snapshot 2026-08-07 grain and month | PASS | rows=12; unique anchor-category=12; duplicate keys=0; data month=['2026-07'] |
| Snapshot 2026-09-04 grain and month | PASS | rows=18; unique anchor-category=18; duplicate keys=0; data month=['2026-08'] |
| Snapshot 2026-10-09 grain and month | PASS | rows=18; unique anchor-category=18; duplicate keys=0; data month=['2026-09'] |
| Repeated October UIDs represent multi-category anchors | PASS | 12 anchors form 18 anchor-category keys; 4 anchors span multiple categories |
| Snapshot overview independently recomputed | PASS | 3 rows and all fields match |
| category summary independently recomputed | PASS | 16 rows and all fields match |
| tier summary independently recomputed | PASS | 3 rows and all fields match |
| Cross-snapshot anchor overlap independently recomputed | PASS | 4 rows and all fields match |
| Snapshot quality checks have no failures | PASS | 22 checks; failures=[] |
| Bilingual SQL risk inventories match | PASS | English=13; Chinese=13; IDs match=True |
| Core SQL tables, dates, and metric structures are present | PASS | missing=[] |
| SQL date strings are zero-padded | PASS | 2026-9-30 is absent; 2026-09-30 is present |
| Product-scope difference between eligibility and DAU is recorded | PASS | SQL-07 is recorded; hmos_kiwi absent from runtime SQL=False |
| Generated deliverables contain no source UID or nickname | PASS | no source UID or nickname found in generated deliverables |
| Bilingual workbooks have the expected structure | PASS | ai-live-room-snapshot-review-zh.xlsx=['快照总览', '品类汇总', 'ACU分层汇总', '主播覆盖重叠', '数据质量', 'SQL静态审查', '方法说明']; ai-live-room-snapshot-review-en.xlsx=['Snapshot overview', 'Category summary', 'Tier summary', 'Anchor overlap', 'Data quality', 'SQL static review', 'Method'] |
| Bilingual project documentation is present | PASS | missing=[] |
| Formal SQL execution and final-metric reconciliation | NOT_RUN | not run=['SQL-11']; results remain static-review only |

Summary: 21 checks, 20 passed, 0 failed, 1 not run, 0 review.

Conclusion: the snapshot files, anonymous summaries, anchor overlap, and privacy boundary are verified. SQL remains under static review; the exports must not be treated as freshly executed and reconciled by the current query.
