# ══════════════════════════════════════════════════════════════════
#  Stratified Sampling — sparklyr (R / Spark)  ✅ CORRECTED
#
#  REQUIRES: sparklyr >= 1.5, Spark >= 3.0
#
#  KEY FIX:  sdf_sample_by() does NOT exist in sparklyr.
#            The correct method is:
#              group_by(strat_key) %>% sample_frac(pct)   -- percentage
#              group_by(strat_key) %>% sample_n(n)        -- fixed count
#            Both are native Spark operations (shipped in sparklyr 1.5).
# ══════════════════════════════════════════════════════════════════

library(sparklyr)   # >= 1.5
library(dplyr)

# ── 0. Spark session ─────────────────────────────────────────────
sc <- spark_connect(master = "local")   # replace with your cluster URL

# ── 1. Load / generate the 10K population ────────────────────────
set.seed(42)
N <- 10000

sports    <- c("Football","Tennis","Padel","Motorsports","Basketball","Cricket","Swimming")
genres    <- c("Drama","Action","Horror","Comedy","PG","Thriller","Romance")
countries <- c("UAE","Qatar","Egypt","Kuwait","Saudi Arabia","Bahrain","Jordan")
languages <- c("Arabic","English","Turkish","French","Hindi")

make_row <- function(i) {
  ct <- sample(c("Sports","Entertainment"), 1, prob = c(0.45, 0.55))
  list(
    UserID      = sample(101:200, 1),
    SportsName  = if (ct == "Sports") sample(sports, 1) else NA_character_,
    ContentType = ct,
    Genre       = if (ct == "Entertainment") sample(genres, 1) else NA_character_,
    Country     = sample(countries, 1, prob = c(0.25,0.20,0.18,0.12,0.12,0.07,0.06)),
    Language    = if (ct == "Entertainment")
                    sample(languages, 1, prob = c(0.35,0.40,0.10,0.08,0.07))
                  else NA_character_,
    TotalMins   = round(rexp(1, rate = 1/50), 1),
    TotalCNT    = as.integer(rexp(1, rate = 1/500))
  )
}

pop_local <- do.call(rbind, lapply(seq_len(N), function(i) as.data.frame(make_row(i))))
pop_sdf   <- copy_to(sc, pop_local, "population", overwrite = TRUE)

# ── 2. Build composite stratification key ────────────────────────
CAT_COLS <- c("ContentType", "Genre", "Country", "Language", "SportsName")

pop_keyed <- pop_sdf %>%
  mutate(across(all_of(CAT_COLS), ~ if_else(is.na(.), "__NA__", as.character(.)))) %>%
  mutate(strat_key = paste(ContentType, Genre, Country, Language, SportsName, sep = " | "))

cat("Unique strata:",
    pop_keyed %>% select(strat_key) %>% distinct() %>% count() %>% collect() %>% pull(n), "\n")

# ══════════════════════════════════════════════════════════════════
#  SCENARIO A — Percentage-based stratified sample
#
#  ✅  group_by(strat_key) %>% sample_frac(size = pct)
#
#  Draws `pct` fraction from EACH stratum independently.
#  Executed as a native Spark operation — no collect() needed.
# ══════════════════════════════════════════════════════════════════

SAMPLE_PCT <- 0.10   # ← change freely: 0.05 = 5%, 0.20 = 20%, etc.

sample_pct_sdf <- pop_keyed %>%
  group_by(strat_key) %>%
  sample_frac(size = SAMPLE_PCT) %>%
  ungroup()

pop_n    <- sdf_nrow(pop_keyed)
samp_n   <- sdf_nrow(sample_pct_sdf)
cat(sprintf(
  "\nScenario A – %.0f%% sample\n  Population : %d\n  Sample     : %d (%.2f%%)\n",
  SAMPLE_PCT * 100, pop_n, samp_n, samp_n / pop_n * 100
))

# ══════════════════════════════════════════════════════════════════
#  SCENARIO B — Fixed-N per stratum  (bonus)
#
#  ✅  group_by(strat_key) %>% sample_n(size = N)
#
#  Draws exactly N rows from every stratum regardless of its size.
#  Useful when you want equal representation across all strata.
# ══════════════════════════════════════════════════════════════════

SAMPLE_N <- 3L   # ← draw exactly 3 rows from every stratum

sample_n_sdf <- pop_keyed %>%
  group_by(strat_key) %>%
  sample_n(size = SAMPLE_N) %>%
  ungroup()

cat(sprintf(
  "\nScenario B – Fixed %d rows/stratum\n  Sample rows: %d\n",
  SAMPLE_N, sdf_nrow(sample_n_sdf)
))

# ══════════════════════════════════════════════════════════════════
#  DISTRIBUTION VALIDATION
#  Compare population vs Scenario A sample for every categorical col
# ══════════════════════════════════════════════════════════════════

compare_distributions <- function(pop_sdf, sample_sdf, cols) {
  results <- lapply(cols, function(col) {
    pop_dist <- pop_sdf %>%
      group_by(!!sym(col)) %>%
      summarise(pop_n = n(), .groups = "drop") %>%
      collect() %>%
      mutate(pop_pct = pop_n / sum(pop_n))

    samp_dist <- sample_sdf %>%
      group_by(!!sym(col)) %>%
      summarise(samp_n = n(), .groups = "drop") %>%
      collect() %>%
      mutate(samp_pct = samp_n / sum(samp_n))

    full_join(pop_dist, samp_dist, by = col) %>%
      mutate(
        pop_pct  = coalesce(pop_pct,  0),
        samp_pct = coalesce(samp_pct, 0),
        abs_diff = abs(pop_pct - samp_pct),
        column   = col
      ) %>%
      rename(level = !!sym(col)) %>%
      mutate(level = as.character(level)) %>%
      select(column, level, pop_pct, samp_pct, abs_diff)
  })
  do.call(rbind, results)
}

validation_df <- compare_distributions(pop_keyed, sample_pct_sdf, CAT_COLS)

cat("\n── Distribution Validation (pop vs stratified sample) ──\n")
print(validation_df, digits = 4)
cat(sprintf("\nMax drift : %.4f (%.2f%%)\n", max(validation_df$abs_diff),  max(validation_df$abs_diff)  * 100))
cat(sprintf("Mean drift: %.4f (%.2f%%)\n",  mean(validation_df$abs_diff), mean(validation_df$abs_diff) * 100))

# ── Save outputs ─────────────────────────────────────────────────
spark_write_csv(pop_keyed      %>% select(-strat_key), "population_10k",        mode = "overwrite")
spark_write_csv(sample_pct_sdf %>% select(-strat_key), "stratified_sample_pct", mode = "overwrite")
write.csv(validation_df, "distribution_validation.csv", row.names = FALSE)
cat("\nFiles saved.\n")

spark_disconnect(sc)
