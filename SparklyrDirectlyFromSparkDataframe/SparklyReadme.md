Exactly right — you've identified a real performance problem. Converting a 2–3M row Spark DataFrame to R with `collect()` is slow and memory-heavy. **Don't do it.**

The right answer is to stay entirely in Spark and use sparklyr's native window functions. Here's the architecture:Now here is the complete corrected sparklyr script — your Spark DataFrame goes straight in, no `collect()` until the final tiny sample comes out:You're 100% right — converting to R first would be a mistake. Here's the exact breakdown of what stays where:

---

## What runs where

| Operation | Where it runs | Data moved to R? |
|---|---|---|
| Build `strat_key` | Spark workers | No |
| `rand()` + `rank()` per stratum | Spark workers | No |
| Compute per-stratum target sizes | R driver | Yes — but only ~300 rows |
| Push sizes back to Spark | R → Spark | Tiny table only |
| `filter(row_rank <= n_take)` | Spark workers | No |
| Distribution validation | Spark workers | Yes — ~50 rows summary |
| Final sample | Spark → R | Yes — ~200K rows, safe |
| **Full population** | **Stays in Spark** | **Never** |

---

## The one important difference from `sample_frac()`

You might wonder — why not just use `group_by() %>% sample_frac()`? Because `sample_frac()` applies the same fraction uniformly and has no floor mechanism. A stratum with 3 rows at 10% gets `round(0.3) = 0` — it disappears silently. The `rand() + rank() + join` window approach lets us compute the per-stratum floor in R on the tiny sizes table, push it back, and filter — all without touching the 2–3M rows in R memory.

---

## How to plug in your existing SDF

Just replace the demo block in Step 1 with however you already have your data:

```r
# From Parquet
pop_sdf <- spark_read_parquet(sc, "my_data", "/data/lake/users.parquet")

# From Hive table
pop_sdf <- tbl(sc, "my_hive_table")

# From a database schema
pop_sdf <- dplyr::tbl(sc, dbplyr::in_schema("db_name", "table_name"))
```

Everything else in the script works identically from that point forward.
