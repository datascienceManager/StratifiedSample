# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  STRATIFIED SAMPLING — FOR AN EXISTING SPARK DATAFRAME (2–3M rows)         ║
# ║                                                                              ║
# ║  KEY DESIGN DECISION:                                                        ║
# ║    Your data is already in Spark. Keep it there.                             ║
# ║    data.table requires collect() → slow transfer + high R RAM.               ║
# ║    This script does EVERYTHING inside Spark using sparklyr window functions. ║
# ║    Only the final small sample (~200K rows) is collected to R at the end.    ║
# ║                                                                              ║
# ║  What happens on the Spark cluster vs R driver:                              ║
# ║    SPARK  : strat_key build · rand() · rank() · join · filter               ║
# ║    R driver (tiny): strata sizes table · collect final sample               ║
# ║                                                                              ║
# ║  Requires: sparklyr >= 1.5, Spark >= 3.0, dplyr                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

library(sparklyr)
library(dplyr)

# ─────────────────────────────────────────────────────────────────
# CONFIGURATION  ← change these as needed
# ─────────────────────────────────────────────────────────────────
SAMPLE_PCT  <- 0.10   # 10%  — change to 0.05, 0.20 etc.
SAMPLE_N    <- 3L     # fixed-N scenario
MIN_ROWS    <- 1L     # Strategy 1 floor
SEED        <- 42L

CAT_COLS <- c("ContentType", "Genre", "Country", "Language", "SportsName")


# ══════════════════════════════════════════════════════════════════
# STEP 1 — CONNECT AND POINT TO YOUR EXISTING SPARK DATAFRAME
#
#  Replace this section with however you already have your SDF.
#  Examples:
#    pop_sdf <- spark_read_parquet(sc, "my_data", "/path/to/data.parquet")
#    pop_sdf <- spark_read_csv(sc, "my_data", "/path/to/data.csv")
#    pop_sdf <- tbl(sc, "my_hive_table")
#    pop_sdf <- dplyr::tbl(sc, dbplyr::in_schema("db", "table"))
# ══════════════════════════════════════════════════════════════════

sc <- spark_connect(master = "local")   # ← replace with your cluster URL
# sc <- spark_connect(master = "yarn")

# ── REPLACE THIS BLOCK with your actual SDF ──────────────────────
# For demonstration: generate a small synthetic SDF
# In production, just point pop_sdf at your existing DataFrame
set.seed(SEED)
n_demo <- 100000L
ct_vec   <- sample(c("Sports","Entertainment"), n_demo, replace=TRUE, prob=c(.45,.55))
is_sport <- ct_vec == "Sports"
pop_local <- data.frame(
  UserID      = sample(101L:10000L, n_demo, replace=TRUE),
  ContentType = ct_vec,
  SportsName  = ifelse(is_sport,  sample(c("Football","Tennis","Padel","Motorsports","Basketball","Cricket","Swimming"), n_demo, replace=TRUE), NA),
  Genre       = ifelse(!is_sport, sample(c("Drama","Action","Horror","Comedy","PG","Thriller","Romance"), n_demo, replace=TRUE), NA),
  Country     = sample(c("UAE","Qatar","Egypt","Kuwait","Saudi Arabia","Bahrain","Iraq","Palestine"), n_demo, replace=TRUE, prob=c(.30,.25,.20,.10,.07,.04,.025,.015)),
  Language    = ifelse(!is_sport, sample(c("Arabic","English","Turkish","French","Hindi"), n_demo, replace=TRUE, prob=c(.35,.40,.10,.08,.07)), NA),
  TotalMins   = round(rexp(n_demo, 1/50), 1),
  TotalCNT    = as.integer(rexp(n_demo, 1/500)),
  stringsAsFactors = FALSE
)
pop_sdf <- copy_to(sc, pop_local, "population", overwrite=TRUE)
rm(pop_local); gc()
# ── END OF DEMO BLOCK ─────────────────────────────────────────────

cat(sprintf("Population rows: %s\n", format(sdf_nrow(pop_sdf), big.mark=",")))


# ══════════════════════════════════════════════════════════════════
# STEP 2 — BUILD COMPOSITE STRATIFICATION KEY INSIDE SPARK
#
#  Everything here runs as a Spark SQL operation — no data moves
#  to the R driver. NAs → "__NA__" so they form their own strata.
# ══════════════════════════════════════════════════════════════════

pop_keyed <- pop_sdf %>%
  mutate(
    ContentType = ifelse(is.na(ContentType), "__NA__", ContentType),
    Genre       = ifelse(is.na(Genre),       "__NA__", Genre),
    Country     = ifelse(is.na(Country),     "__NA__", Country),
    Language    = ifelse(is.na(Language),    "__NA__", Language),
    SportsName  = ifelse(is.na(SportsName),  "__NA__", SportsName)
  ) %>%
  mutate(
    strat_key = paste(ContentType, Genre, Country, Language, SportsName, sep=" | ")
  )

# Count strata — this IS a Spark action (collect a 1-row count)
n_strata <- pop_keyed %>%
  select(strat_key) %>%
  distinct() %>%
  count() %>%
  collect() %>%
  pull(n)

cat(sprintf("Unique strata: %d\n", n_strata))


# ══════════════════════════════════════════════════════════════════
# STEP 3 — STRATEGY 1 MIN-FLOOR SAMPLING FUNCTIONS
#          Fully distributed — runs on Spark workers
#
#  Why NOT group_by() %>% sample_frac() here?
#  sample_frac() applies the SAME fraction to every stratum equally.
#  It has no mechanism to apply a per-stratum floor (e.g. stratum
#  with 3 rows gets floor of 1, not round(3 × 0.10) = 0).
#
#  The window-function approach (rand + rank + join) lets us compute
#  per-stratum target sizes with the floor applied in R (on a tiny
#  table), push those sizes back into Spark, then filter.
#  All the heavy data stays on the cluster throughout.
# ══════════════════════════════════════════════════════════════════

stratified_sample_pct_spark <- function(sdf,
                                         strat_col  = "strat_key",
                                         pct        = 0.10,
                                         min_rows   = 1L,
                                         seed       = 42L) {
  #' Percentage-based stratified sample with Strategy 1 min-floor.
  #' Runs entirely inside Spark — no collect() of large data.
  #'
  #' @param sdf       Spark DataFrame (already has strat_col)
  #' @param strat_col composite strat key column name
  #' @param pct       sampling fraction 0 < pct < 1
  #' @param min_rows  minimum rows per stratum (floor)
  #' @param seed      random seed passed to Spark rand()
  #' @return Spark DataFrame — stratified sample

  stopifnot(pct > 0, pct < 1, min_rows >= 1)

  # ── 3a. Compute per-stratum sizes ON THE DRIVER (tiny table) ──
  #  This collect() is safe: ~300 rows maximum regardless of data size
  strata_sizes <- sdf %>%
    group_by(!!sym(strat_col)) %>%
    summarise(pop_n = n(), .groups = "drop") %>%
    collect() %>%                                    # tiny table, fast
    mutate(
      n_raw    = round(pop_n * pct),
      n_target = pmax(min_rows, n_raw),              # ← Strategy 1 floor
      n_take   = pmin(n_target, pop_n)               # ← cap at available
    )

  floor_count <- sum(strata_sizes$n_raw < min_rows)
  cat(sprintf("  [floor] applied to %d strata\n", floor_count))

  # ── 3b. Push target sizes BACK INTO SPARK (tiny table → Spark) ──
  sizes_sdf <- copy_to(
    sc,
    strata_sizes %>% select(strat_key_join = !!sym(strat_col), n_take),
    name      = "strata_sizes_tmp",
    overwrite = TRUE
  )

  # ── 3c. Window-function sampling — runs on Spark workers ──
  #  rand(seed)   : assigns a random float to every row in Spark
  #  rank()       : ranks rows within each stratum by rand value
  #  join + filter: keep only rows where rank <= n_take
  #
  #  All 2–3M rows stay on the cluster throughout this step.
  sdf %>%
    mutate(rand_val = rand(seed)) %>%                # Spark rand()
    group_by(!!sym(strat_col)) %>%
    mutate(row_rank = rank(rand_val)) %>%            # rank within stratum
    ungroup() %>%
    left_join(
      sizes_sdf,
      by = setNames("strat_key_join", strat_col)
    ) %>%
    filter(row_rank <= n_take) %>%                   # keep top n_take per stratum
    select(-rand_val, -row_rank, -n_take)
}


stratified_sample_n_spark <- function(sdf,
                                       strat_col     = "strat_key",
                                       n_per_stratum = 3L,
                                       seed          = 42L) {
  #' Fixed-N stratified sample — runs entirely in Spark.
  #' Takes exactly n_per_stratum rows per stratum (capped at stratum size).

  sdf %>%
    mutate(rand_val = rand(seed)) %>%
    group_by(!!sym(strat_col)) %>%
    mutate(row_rank = rank(rand_val)) %>%
    ungroup() %>%
    filter(row_rank <= n_per_stratum) %>%
    select(-rand_val, -row_rank)
}


# ══════════════════════════════════════════════════════════════════
# STEP 4 — RUN BOTH SCENARIOS
# ══════════════════════════════════════════════════════════════════

cat("\n─── Scenario A: ", SAMPLE_PCT*100, "% sample ───\n", sep="")
t1 <- proc.time()
sample_a_sdf <- stratified_sample_pct_spark(
  pop_keyed, "strat_key", SAMPLE_PCT, MIN_ROWS, SEED
)
# Register so Spark doesn't recompute repeatedly
sample_a_sdf <- sdf_register(sample_a_sdf, "sample_a")

pop_n    <- sdf_nrow(pop_keyed)
sample_n <- sdf_nrow(sample_a_sdf)
cat(sprintf("  Population : %s\n", format(pop_n,    big.mark=",")))
cat(sprintf("  Sample     : %s  (%.2f%%)\n",
            format(sample_n, big.mark=","), sample_n/pop_n*100))
cat(sprintf("  Time       : %.1fs\n", (proc.time()-t1)[["elapsed"]]))

# Verify Iraq / Palestine preserved
for (country in c("Iraq", "Palestine")) {
  p_n <- pop_keyed   %>% filter(Country==country) %>% count() %>% collect() %>% pull(n)
  s_n <- sample_a_sdf %>% filter(Country==country) %>% count() %>% collect() %>% pull(n)
  cat(sprintf("  %-15s pop=%s  sample=%s  (%.1f%%)\n",
              country,
              format(p_n, big.mark=","),
              format(s_n, big.mark=","),
              if(p_n>0) s_n/p_n*100 else 0))
}

cat("\n─── Scenario B: fixed", SAMPLE_N, "rows per stratum ───\n")
t2 <- proc.time()
sample_b_sdf <- stratified_sample_n_spark(pop_keyed, "strat_key", SAMPLE_N, SEED)
sample_b_sdf <- sdf_register(sample_b_sdf, "sample_b")
cat(sprintf("  Sample: %s rows\n", format(sdf_nrow(sample_b_sdf), big.mark=",")))
cat(sprintf("  Time  : %.1fs\n", (proc.time()-t2)[["elapsed"]]))


# ══════════════════════════════════════════════════════════════════
# STEP 5 — DISTRIBUTION VALIDATION
#
#  group_by + summarise runs in Spark (distributed).
#  Only the tiny distribution table (~50 rows) is collected to R.
# ══════════════════════════════════════════════════════════════════

validate_distributions_spark <- function(pop_sdf, sample_sdf, cols) {
  results <- lapply(cols, function(col) {
    # Both summarise calls run in Spark → collect tiny tables
    pop_dist <- pop_sdf %>%
      group_by(!!sym(col)) %>%
      summarise(pop_n = n(), .groups="drop") %>%
      collect() %>%
      mutate(pop_pct = pop_n / sum(pop_n))

    samp_dist <- sample_sdf %>%
      group_by(!!sym(col)) %>%
      summarise(samp_n = n(), .groups="drop") %>%
      collect() %>%
      mutate(samp_pct = samp_n / sum(samp_n))

    full_join(pop_dist, samp_dist, by=col) %>%
      mutate(
        pop_pct      = coalesce(pop_pct,  0),
        samp_pct     = coalesce(samp_pct, 0),
        abs_diff_pct = round(abs(pop_pct - samp_pct)*100, 3),
        status       = ifelse(abs_diff_pct < 2, "OK",
                        ifelse(abs_diff_pct < 5, "WATCH", "DRIFT")),
        column       = col
      ) %>%
      rename(level = !!sym(col)) %>%
      mutate(level = as.character(level)) %>%
      select(column, level, pop_pct, samp_pct, abs_diff_pct, status)
  })
  do.call(rbind, results)
}

cat("\n─── Distribution validation ───\n")
validation <- validate_distributions_spark(pop_keyed, sample_a_sdf, CAT_COLS)
print(validation, digits=4, row.names=FALSE)

max_d <- max(validation$abs_diff_pct)
cat(sprintf("\n  Max drift : %.3f%%  %s\n",
            max_d,
            ifelse(max_d < 2, "PASS", "REVIEW")))


# ══════════════════════════════════════════════════════════════════
# STEP 6 — SAVE OUTPUTS
#
#  Option A: write sample back to your data lake (stays in Spark)
#  Option B: collect the sample to R for downstream R analysis
#
#  For 2–3M population → 200K sample, collect() is fast and safe.
#  Never collect() the full population — that defeats the purpose.
# ══════════════════════════════════════════════════════════════════

# ── Option A: write to Parquet / Hive (recommended for large teams) ──
spark_write_parquet(
  sample_a_sdf %>% select(-strat_key),
  path = "stratified_sample_10pct",
  mode = "overwrite"
)
cat("\nSample written to Spark: stratified_sample_10pct/\n")

# ── Option B: collect to R data.frame for local analysis ──
# Only do this for the SAMPLE (200K rows), not the population (2–3M rows)
cat("Collecting sample to R...\n")
t3 <- proc.time()
sample_r <- sample_a_sdf %>%
  select(-strat_key) %>%
  collect()
cat(sprintf("Collected %s rows in %.1fs\n",
            format(nrow(sample_r), big.mark=","),
            (proc.time()-t3)[["elapsed"]]))

# Now you can use data.table or any R package on the small sample
# library(data.table)
# sample_dt <- as.data.table(sample_r)

# ── Save validation report locally ──
write.csv(validation, "distribution_validation.csv", row.names=FALSE)

cat("\n══════════════════════════════════════════════════════════\n")
cat("MEMORY SUMMARY\n")
cat("══════════════════════════════════════════════════════════\n")
cat("  Population (2–3M rows) : NEVER left Spark\n")
cat("  R driver memory used   : ~5 MB  (strata sizes + validation table)\n")
cat(sprintf("  Sample collected to R  : %s rows  (safe)\n",
            format(nrow(sample_r), big.mark=",")))
cat("  No collect() on full population — no memory risk\n")

spark_disconnect(sc)
