# SQL Learning Notes

The main learning notebook is [SQL学习笔记.md](SQL学习笔记.md). These are Presto teaching examples, not a validated production analysis.

## Assigning an observation start

VIP buyers have a purchase timestamp; ordinary users need an observation start. The expression below chooses one numbered VIP row and borrows its purchase timestamp:

```sql
mod(crc32(to_utf8(n.uid)), s.start_cnt) + 1 = s.start_no
```

`to_utf8` encodes the UID, `crc32` computes a deterministic integer checksum, `mod` returns a remainder from zero to the VIP count minus one, and adding one maps it to a VIP row number. Ordinary users do not have a stored row number: the expression computes a selection number during the join.

With three VIP rows, illustrative checksums 10 and 13 both select row 2. These are arithmetic examples, not claimed checksum outputs for actual UIDs. Multiple ordinary users can borrow the same start. Each ordinary user gets exactly one start only if VIP numbering is unique and contiguous and the VIP pool is nonempty. Stable ordering by purchase timestamp and UID makes assignment repeatable for an unchanged VIP pool. CRC32 is neither encryption nor a unique identifier. Assignment is not sampling or one-to-one matching; date proportions are not guaranteed to match exactly.

## Activity threshold and conversion

Count distinct active dates in the 30 calendar days before each start, excluding its date. Among eligible VIP buyers with no positive consumption in the preceding 12 months, calculate the mean activity and round upward once. Apply that same threshold to both groups, require no preceding-year consumption, and compare consumption within `[start, start + 30 days)`.

This is a rough common threshold, not propensity score matching. It does not guarantee equal mean activity or causal comparability. Verify complete observation windows and inspect activity and start-date distributions after filtering.

## Arrays and Lambda expressions

`array_agg(distinct cast(dt as date))` creates a list of unique active dates, not a day count. Element order is not guaranteed without explicit ordering. In `filter(pay_times, t -> condition)`, `t` is a locally defined variable representing each payment timestamp. `cardinality` counts the filtered elements. A `CASE WHEN cardinality(...) > 0 THEN 1 ELSE 0 END` flags an existing qualifying payment and returns zero for a missing array.

An alternative uses `max(case when order_ts >= date_add('month', -12, start_ts) and order_ts < start_ts then 1 else 0 end)` on payment detail rows. It requires a detail join and grouping; the expression cannot simply replace an array expression without changing its input.

## Other lessons

- A UID-only `union` can filter payment records without carrying group labels. Analysis cohorts should explicitly retain group labels. `union` deduplicates; `union all` preserves rows.
- Date weighting averages ordinary-user rates using VIP purchase-date counts. It controls date composition, not activity. A user included under multiple start dates cannot be counted as multiple distinct people.
- In Huya work, reserve `anchor` for broadcasters and use `start_date` for observation dates.
- Thirty days differ from a calendar month. Missing partitions differ from no behavior. Preserve the existing positive-consumption definition unless a gift-only definition is explicitly agreed.
- Check unique assignment, disjoint cohorts, full history and follow-up coverage, activity between zero and 30 days, numerator no greater than denominator, and floating-point division.

These notes contain no raw user records, credentials, or production result claims.
