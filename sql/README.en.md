# SQL Reference Archive

The `source/` directory preserves 240 `.sql` files and 2 SQL-formatted `.txt` files from the original `Desktop\SQL` source. Original file names and relative directories are retained; SQL definitions were not rewritten.

The `source/月报附录/` subdirectory separately preserves four original SQL files from `Desktop\月报_附录`; they are not included in the 240-file `Desktop\SQL` count. Project context, anonymized results, and defects are documented at `projects/monthly-report-appendix/`.

The source directory also contains 54 CSV files, 22 Excel files, 25 Python scripts, and other files. CSV and Excel data were not copied. The Python scripts and the `content_categories_full.txt` category text remain queued for project review and inclusion decisions.

A scan for common credential formats found no matches in the copied SQL text. Reviewed topic indexes are kept under `topics/`; the first is [`topics/retention-analytics/`](topics/retention-analytics/README.en.md), covering external Douyu/Bilibili/Douyin and Huya Star Show danmu/gift retention dependencies, definitions, version choices, and known defects. The source archive remains unchanged.

The `reference/` directory stores cross-project SQL lookup values. It currently includes [`common-anchor-and-game-id-maps.en.md`](reference/common-anchor-and-game-id-maps.en.md), which records the common anchor IDs, assigned business categories, and `game_id` values supplied by the user on 2026-11-03. These are convenience filters, not substitutes for the platform dimension tables.

[`SQL学习笔记.en.md`](SQL学习笔记.en.md) provides learning notes on observation-start assignment, CRC32 and modulo, arrays and Lambda expressions, activity thresholds, and date weighting. Examples are teaching snippets, not validated production SQL.

Chinese version: `README.md`.

[Daily denominator SQL and sarcasm-classification lessons](topics/ad-complaint-texts-20261113/README.en.md) for ad viewing-experience complaints. Preserves the supplied user definition; SQL remains unexecuted and unvalidated.
