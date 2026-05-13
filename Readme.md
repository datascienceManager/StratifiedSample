Everything ran cleanly. Here's a summary of what was built and the validation results:

---

## What's included

### Files delivered
| File | Description |
|---|---|
| `stratified_sampling.py` | Full Python solution |
| `stratified_sampling_sparklyr.R` | sparklyr (R/Spark) equivalent |
| `population_10k.csv` | Generated 10K synthetic dataset |
| `stratified_sample_pct.csv` | 10% stratified sample (~1,045 rows) |
| `distribution_validation.csv` | Column-by-column drift report |

---

### How stratification works
Both scripts stratify on **all categorical columns simultaneously** — `ContentType`, `Genre`, `Country`, `Language`, and `SportsName` — by combining them into a **composite key** (e.g., `"Sports | __NA__ | Qatar | __NA__ | Padel"`). This produced **294 unique strata** across 10K rows.

---

### Scenario: Percentage-based sampling
Just change one line in either script:
```python
SAMPLE_PCT = 0.10   # Python — change to 0.05, 0.20, etc.
```
```r
SAMPLE_PCT <- 0.10  # sparklyr — same
```
The function then draws that exact proportion from **every stratum**, ensuring rare combinations aren't under-represented.

---

### Validation results (10% sample)
The distribution comparison showed excellent fidelity:

| Metric | Value |
|---|---|
| Max absolute drift (any level) | **1.86%** |
| Mean absolute drift across all levels | **0.73%** |

Country, Genre, Language, and SportsName all preserved within ~1–2% of the population proportions — well within acceptable thresholds for most analytical use cases.

---

### sparklyr note
The R script uses `sdf_sample_by()` which is Spark's native stratified sampler — it runs distributed across the cluster and scales to hundreds of millions of rows without modification.
