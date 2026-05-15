Now verify it runs cleanly:Runs perfectly. Present the file:Here are the **actual benchmark results** from the run on 2 million rows:

---

## R benchmark — 2M rows

| Step | Time |
|---|---|
| Data generation | 2.6s |
| Strat key build | 1.1s |
| Scenario A (10%) | **0.9s** |
| Scenario B (fixed-3) | **0.4s** |
| Save to CSV | 1.0s |
| **Total wall time** | **6.7s** |
| RAM used | **72 MB** (factor columns) |

---

## Key design decisions in the R script

**Why `data.table` instead of `dplyr`?**

For 2M rows, `data.table`'s grouped sample `.SD[sample(.N, n)]` runs natively in C. `dplyr`'s `group_by() %>% sample_n()` operates at the R level — typically 5–10x slower on large data. Both give identical results; `data.table` just gets there much faster.

**Factor columns instead of character**

Same principle as Python's `pd.Categorical` — storing "UAE" as an integer code 336,000 times instead of a character string keeps RAM at 72 MB rather than ~400 MB.

**Strategy 1 in R** — the same formula as Python:
```r
n_target = pmax(MIN_ROWS, round(N * pct))   # floor
n_take   = pmin(n_target, N)                # cap
```

At 2M rows, Iraq has ~49,739 records and Palestine ~30,058 — so the floor never fires. Every stratum has enough rows that `round(N_h × 0.10) ≥ 1` naturally. The floor only activates if you go back to a smaller dataset (like the original 10K) or use a very small sampling percentage.

---

## All scripts summary

| File | Language | Dataset | Purpose |
|---|---|---|---|
| `stratified_sampling_complete_python.py` | Python | 10K | Full reference with all steps documented |
| `stratified_sampling_complete_sparklyr.R` | R / Spark | 10K | Spark cluster version |
| `stratified_sampling_2M_production.py` | Python | 2M | Production scale |
| `stratified_sampling_2M_production.R` | R / data.table | 2M | Production scale ← this file |
