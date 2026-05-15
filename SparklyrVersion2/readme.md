sparklyr — with Strategy 1 fully integrated, clean, and production-ready.Clean. Now write the sparklyr version:Both scripts ran cleanly. Here's a full summary of what's in each file and the references behind the approach:

---

## What's in each file

Both scripts cover the **exact same 7-step flow**, just in different languages:

| Step | What it does |
|---|---|
| 1 | Generate 10K dataset — UAE/Qatar/Egypt large, Iraq (~244) / Palestine (~145) intentionally sparse |
| 2 | Build composite `strat_key` from all 5 categorical columns; NaN → `__NA__` |
| 3 | Report strata sizes — shows 21 strata with 1 row, 84 strata with <5 rows |
| 4 | **Strategy 1 function** — `n_take = max(MIN_ROWS, round(N_h × pct))` — floor applied to 92 strata |
| 5 | Run Scenario A (10%) and Scenario B (fixed-3) |
| 6 | Distribution validation across all columns — max drift 3.09%, all ✅ OK |
| 7 | Save all outputs |

---

## What Strategy 1 actually did (from the run)

```
Without floor:  92 strata would have sampled 0 rows
With floor=1 :  all 327 strata represented

Iraq      → population 244  |  sample 42  (17.2% represented)
Palestine → population 145  |  sample 39  (26.9% represented)
Max drift across all levels: 3.09%  ✅ PASS
```

---

## Academic References

**Cochran, W.G. (1977). *Sampling Techniques*, 3rd edition. Wiley.**
The foundational textbook on stratified sampling. Chapter 5 defines proportional allocation as `n_h = n × (N_h / N)` and explicitly discusses the need for a minimum sample floor when strata are very small.

**SAGE Encyclopedia of Educational Research, Measurement and Evaluation (2018):**
"Stratified sampling ensures that at least one observation is picked from each stratum, even if the proportion of population units in a particular stratum is close to 0."

**sparklyr 1.5 (RStudio, 2020):** Stratified sampling on Spark DataFrames uses `dplyr::group_by()` followed by `dplyr::sample_frac()` or `dplyr::sample_n()` — shipped in sparklyr 1.5 for Spark 3.0+.

**stattrek.com — Stratified Sampling:** Proportionate stratification sets each stratum's sample size proportionate to the population size of that stratum, using `n_h = (N_h / N) × n`.
