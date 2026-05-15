# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║     STRATIFIED SAMPLING — COMPLETE SPARKLYR SCRIPT (Strategy 1 integrated) ║
# ║                                                                              ║
# ║  Schema  : UserID · SportsName · ContentType · Genre · Country · Language   ║
# ║            TotalMins · TotalCNT                                              ║
# ║                                                                              ║
# ║  Strategy: Minimum-Floor Proportional Stratified Sampling                   ║
# ║    • Stratify on ALL categorical columns simultaneously (composite key)      ║
# ║    • Scenario A — percentage-based  (e.g. 10%)                              ║
# ║    • Scenario B — fixed-N per stratum (e.g. 3 rows)                         ║
# ║    • Small-stratum safeguard: always keep ≥ MIN_ROWS rows per stratum        ║
# ║      (prevents tiny strata like Iraq / Palestine from disappearing)          ║
# ║    • Distribution validation — proves sample ≈ population                   ║
# ║                                                                              ║
# ║  REQUIRES : sparklyr >= 1.5,  Spark >= 3.0,  dplyr                          ║
# ║                                                                              ║
# ║  CORRECT sparklyr sampling API (v1.5+):                                     ║
# ║    group_by(strat_key) %>% sample_frac(size = pct)   ← Scenario A           ║
# ║    group_by(strat_key) %>% sample_n(size = N)        ← Scenario B           ║
# ║    NOTE: sdf_sample_by() does NOT exist in sparklyr                          ║
# ║                                                                              ║
# ║  Reference:                                                                  ║
# ║    Cochran, W.G. (1977). Sampling Techniques (3rd ed.). Wiley.               ║
# ║      — Ch.5 proportional allocation: n_h = n × (N_h / N)                    ║
# ║      — Minimum-floor: guaranteed ≥1 observation per stratum                 ║
# ║                                                                              ║
# ║    SAGE Encyclopedia of Educational Research (2018):                         ║
# ║      "Stratified sampling ensures that at least one observation is picked    ║
# ║       from each stratum, even if the proportion of population units in a     ║
# ║       particular stratum is close to 0."                                     ║
# ║      https://methods.sagepub.com/ency/edvol/                                 ║
# ║        sage-encyclopedia-of-educational-research-measurement-evaluation/    ║
# ║        chpt/stratified-random-sampling                                       ║
# ║                                                                              ║
# ║    sparklyr 1.5 release (RStudio, 2020):                                     ║
# ║      "Stratified sampling on Spark DataFrames: group_by() + sample_frac()"  ║
# ║      https://www.r-bloggers.com/2020/12/sparklyr-1-5-better-dplyr-interface ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

library(sparklyr)   # >= 1.5
library(dplyr)

# ─────────────────────────────────────────────────────────────────
# CONFIGURATION  ← change these as needed
# ─────────────────────────────────────────────────────────────────
SEED       <- 42L
SAMPLE_PCT <- 0.10   # Scenario A: 10%  (try 0.05, 0.20, etc.)
SAMPLE_N   <- 3L     # Scenario B: fixed 3 rows per stratum
MIN_ROWS   <- 1L     # Strategy 1 floor (minimum rows per stratum)


# ══════════════════════════════════════════════════════════════════
# STEP 1 — SPARK SESSION
# ══════════════════════════════════════════════════════════════════
sc <- spark_connect(master = "local")   # replace with your cluster URL
# sc <- spark_connect(master = "yarn")


# ══════════════════════════════════════════════════════════════════
# STEP 2 — GENERATE 10K SYNTHETIC DATASET
# ══════════════════════════════════════════════════════════════════
set.seed(SEED)
N <- 10000L

sports    <- c("Football","Tennis","Padel","Motorsports","Basketball","Cricket","Swimming")
genres    <- c("Drama","Action","Horror","Comedy","PG","Thriller","Romance")
languages <- c("Arabic","English","Turkish","French","Hindi")
countries <- c("UAE","Qatar","Egypt","Kuwait","Saudi Arabia","Bahrain","Iraq","Palestine")
country_p <- c(0.30, 0.25, 0.20, 0.10, 0.07, 0.04, 0.025, 0.015)

make_row <- function(i) {
  ct <- sample(c("Sports","Entertainment"), 1L, prob = c(0.45, 0.55))
  list(
    UserID      = sample(101L:300L, 1L),
    ContentType = ct,
    SportsName  = if (ct == "Sports") sample(sports, 1L)                              else NA_character_,
    Genre       = if (ct == "Entertainment") sample(genres, 1L)                       else NA_character_,
    Country     = sample(countries, 1L, prob = country_p),
    Language    = if (ct == "Entertainment")
                    sample(languages, 1L, prob = c(0.35, 0.40, 0.10, 0.08, 0.07))
                  else NA_character_,
    TotalMins   = round(rexp(1L, rate = 1/50), 1L),
    TotalCNT    = as.integer(rexp(1L, rate = 1/500))
  )
}

pop_local <- do.call(rbind, lapply(seq_len(N), function(i) as.data.frame(make_row(i))))
pop_sdf   <- copy_to(sc, pop_local, "population", overwrite = TRUE)

cat("═══════════════════════════════════════════════════════════\n")
cat("POPULATION OVERVIEW\n")
cat("═══════════════════════════════════════════════════════════\n")
cat(sprintf("  Rows: %s\n", format(sdf_nrow(pop_sdf), big.mark = ",")))
cat("\n  Country distribution:\n")
pop_sdf %>% count(Country, sort = TRUE) %>% collect() %>%
  { for (i in seq_len(nrow(.))) cat(sprintf("    %-15s %4d\n", .[[i,1]], .[[i,2]])) }


# ══════════════════════════════════════════════════════════════════
# STEP 3 — BUILD COMPOSITE STRATIFICATION KEY
#           All NAs → "__NA__" so they form their own strata
# ══════════════════════════════════════════════════════════════════
CAT_COLS <- c("ContentType", "Genre", "Country", "Language", "SportsName")

pop_keyed <- pop_sdf %>%
  mutate(across(all_of(CAT_COLS),
                ~ if_else(is.na(.), "__NA__", as.character(.)))) %>%
  mutate(strat_key = paste(ContentType, Genre, Country, Language, SportsName,
                           sep = " | "))

n_strata <- pop_keyed %>% select(strat_key) %>% distinct() %>% count() %>%
            collect() %>% pull(n)
cat(sprintf("\n  Total unique strata: %d\n", n_strata))


# ══════════════════════════════════════════════════════════════════
# STEP 4 — STRATEGY 1: MINIMUM-FLOOR SAMPLING FUNCTIONS
#
#  sparklyr approach (v1.5+):
#    group_by(strat_key) %>% sample_frac(size = pct)
#
#  For the minimum-floor safeguard we cannot pass per-stratum
#  fractions to sample_frac/sample_n directly.  Instead:
#    1. Compute per-stratum sizes in a driver-side table
#    2. Clamp n_h = max(MIN_ROWS, round(N_h * pct))
#    3. Join back to the SDF and use a window-function row_number()
#       to select exactly n_h rows per stratum
#
#  This keeps all computation on Spark — no per-stratum collect().
# ══════════════════════════════════════════════════════════════════

stratified_sample_pct_floor <- function(sdf, strat_col, pct,
                                         min_rows = 1L, seed = SEED) {
  # ── 4a. Compute per-stratum target sizes (driver side, tiny table) ──
  strata_sizes <- sdf %>%
    group_by(!!sym(strat_col)) %>%
    summarise(pop_n = n(), .groups = "drop") %>%
    collect() %>%
    mutate(
      n_raw    = round(pop_n * pct),
      n_target = pmax(min_rows, n_raw),        # ← Strategy 1 floor
      n_take   = pmin(n_target, pop_n)         # ← never exceed available
    )

  floor_count <- sum(strata_sizes$n_raw < min_rows)
  cat(sprintf("\n  [floor] applied to %d strata (would have sampled 0 at %.0f%%)\n",
              floor_count, pct * 100))

  # ── 4b. Push sizes back to Spark ──
  sizes_sdf <- copy_to(sc, strata_sizes %>% select(!!strat_col := !!sym(strat_col),
                                                     n_take),
                        "strata_sizes_tmp", overwrite = TRUE)

  # ── 4c. Assign random row numbers within each stratum, then filter ──
  sdf %>%
    mutate(rand_val = rand(seed)) %>%
    group_by(!!sym(strat_col)) %>%
    mutate(row_rank = rank(rand_val)) %>%      # row_number within stratum
    ungroup() %>%
    left_join(sizes_sdf, by = strat_col) %>%
    filter(row_rank <= n_take) %>%
    select(-rand_val, -row_rank, -n_take) %>%
    sdf_register("sample_pct_floor")
}


stratified_sample_n_floor <- function(sdf, strat_col, n_per_stratum,
                                       seed = SEED) {
  # Fixed-N: take exactly n_per_stratum rows, but cap at stratum size
  sdf %>%
    mutate(rand_val = rand(seed)) %>%
    group_by(!!sym(strat_col)) %>%
    mutate(row_rank = rank(rand_val)) %>%
    ungroup() %>%
    filter(row_rank <= n_per_stratum) %>%
    select(-rand_val, -row_rank) %>%
    sdf_register("sample_n_floor")
}


# ══════════════════════════════════════════════════════════════════
# STEP 5 — RUN BOTH SCENARIOS
# ══════════════════════════════════════════════════════════════════

cat("\n═══════════════════════════════════════════════════════════\n")
cat(sprintf("SCENARIO A — PERCENTAGE-BASED SAMPLE (%.0f%%)\n", SAMPLE_PCT * 100))
cat("═══════════════════════════════════════════════════════════\n")

sample_pct_sdf <- stratified_sample_pct_floor(pop_keyed, "strat_key",
                                               SAMPLE_PCT, MIN_ROWS, SEED)

pop_n    <- sdf_nrow(pop_keyed)
samp_n_a <- sdf_nrow(sample_pct_sdf)
cat(sprintf("  Population : %s rows\n", format(pop_n,    big.mark = ",")))
cat(sprintf("  Sample     : %s rows  (%.2f%% of population)\n",
            format(samp_n_a, big.mark = ","), samp_n_a / pop_n * 100))

# Verify Iraq / Palestine preserved
for (country in c("Iraq", "Palestine")) {
  p_n <- pop_keyed   %>% filter(Country == country) %>% count() %>% collect() %>% pull(n)
  s_n <- sample_pct_sdf %>% filter(Country == country) %>% count() %>% collect() %>% pull(n)
  cat(sprintf("  %-15s — population: %3d | sample: %3d (%.1f%% represented)\n",
              country, p_n, s_n, if (p_n > 0) s_n/p_n*100 else 0))
}


cat("\n═══════════════════════════════════════════════════════════\n")
cat(sprintf("SCENARIO B — FIXED-N SAMPLE (%d rows per stratum)\n", SAMPLE_N))
cat("═══════════════════════════════════════════════════════════\n")

sample_n_sdf <- stratified_sample_n_floor(pop_keyed, "strat_key", SAMPLE_N, SEED)

samp_n_b <- sdf_nrow(sample_n_sdf)
cat(sprintf("  Sample: %s rows\n", format(samp_n_b, big.mark = ",")))
for (country in c("Iraq", "Palestine")) {
  p_n <- pop_keyed   %>% filter(Country == country) %>% count() %>% collect() %>% pull(n)
  s_n <- sample_n_sdf %>% filter(Country == country) %>% count() %>% collect() %>% pull(n)
  cat(sprintf("  %-15s — population: %3d | sample: %3d\n", country, p_n, s_n))
}


# ══════════════════════════════════════════════════════════════════
# STEP 6 — DISTRIBUTION VALIDATION
#           Compare pop % vs sample % for each categorical column
# ══════════════════════════════════════════════════════════════════

validate_distributions <- function(pop_sdf, sample_sdf, cols) {
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
        pop_pct      = coalesce(pop_pct,  0),
        samp_pct     = coalesce(samp_pct, 0),
        abs_diff_pct = round(abs(pop_pct - samp_pct) * 100, 2),
        status       = if_else(abs_diff_pct < 5, "OK", "DRIFT"),
        column       = col
      ) %>%
      rename(level = !!sym(col)) %>%
      mutate(level = as.character(level)) %>%
      select(column, level, pop_pct, samp_pct, abs_diff_pct, status)
  })
  do.call(rbind, results)
}

cat("\n═══════════════════════════════════════════════════════════\n")
cat(sprintf("DISTRIBUTION VALIDATION — Scenario A (%.0f%% sample)\n", SAMPLE_PCT*100))
cat("═══════════════════════════════════════════════════════════\n")

validation_df <- validate_distributions(pop_keyed, sample_pct_sdf, CAT_COLS)
print(validation_df, digits = 4)

max_drift  <- max(validation_df$abs_diff_pct)
mean_drift <- mean(validation_df$abs_diff_pct)
n_drifted  <- sum(validation_df$abs_diff_pct >= 5)

cat(sprintf("\n  Max drift  : %.2f%%\n", max_drift))
cat(sprintf("  Mean drift : %.2f%%\n", mean_drift))
cat(sprintf("  Levels with drift >= 5%%: %d\n", n_drifted))
cat(sprintf("  %s\n",
    if (max_drift < 5) "PASS — sample is representative."
    else               "REVIEW — some levels show >5% drift."))


# ══════════════════════════════════════════════════════════════════
# STEP 7 — SAVE OUTPUTS
# ══════════════════════════════════════════════════════════════════

spark_write_csv(pop_keyed      %>% select(-strat_key), "population_10k",        mode = "overwrite")
spark_write_csv(sample_pct_sdf %>% select(-strat_key), "sample_pct_10pct",      mode = "overwrite")
spark_write_csv(sample_n_sdf   %>% select(-strat_key), "sample_fixed_n",        mode = "overwrite")
write.csv(validation_df, "distribution_validation.csv", row.names = FALSE)

cat("\n═══════════════════════════════════════════════════════════\n")
cat("FILES SAVED\n")
cat("═══════════════════════════════════════════════════════════\n")
cat("  population_10k/         — full 10K population\n")
cat("  sample_pct_10pct/       — Scenario A: 10% stratified sample\n")
cat("  sample_fixed_n/         — Scenario B: fixed-N stratified sample\n")
cat("  distribution_validation.csv — drift report\n")

spark_disconnect(sc)
