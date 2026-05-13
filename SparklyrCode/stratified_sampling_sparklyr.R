# ══════════════════════════════════════════════════════════════════
#  Stratified Sampling — sparklyr (R)
#  Works on a 10K dataset; scales to 100M+ rows on a Spark cluster
# ══════════════════════════════════════════════════════════════════

library(sparklyr)
library(dplyr)

# ── 0. Spark session ─────────────────────────────────────────────
sc <- spark_connect(master = "local")   # replace "local" with your cluster URL

# ── 1. Load / generate the 10K population ────────────────────────
#   (swap copy_to for spark_read_csv / spark_read_parquet in production)
set.seed(42)
N <- 10000

sports      <- c("Football","Tennis","Padel","Motorsports","Basketball","Cricket","Swimming")
genres      <- c("Drama","Action","Horror","Comedy","PG","Thriller","Romance")
countries   <- c("UAE","Qatar","Egypt","Kuwait","Saudi Arabia","Bahrain","Jordan")
languages   <- c("Arabic","English","Turkish","French","Hindi")
content_types <- c("Sports","Entertainment")

make_row <- function(i) {
  ct <- sample(content_types, 1, prob = c(0.45, 0.55))
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
#    Covers ALL categorical columns; NA → "__NA__"
CAT_COLS <- c("ContentType", "Genre", "Country", "Language", "SportsName")

pop_keyed <- pop_sdf %>%
  mutate(across(all_of(CAT_COLS), ~ if_else(is.na(.), "__NA__", as.character(.)))) %>%
  mutate(strat_key = paste(ContentType, Genre, Country, Language, SportsName, sep = " | "))

n_strata <- pop_keyed %>% select(strat_key) %>% distinct() %>% count() %>% collect()
cat("Unique strata:", n_strata$n, "\n")

# ══════════════════════════════════════════════════════════════════
# SCENARIO A — Percentage-based stratified sample
# ══════════════════════════════════════════════════════════════════
SAMPLE_PCT <- 0.10    # ← change to any fraction: 0.05 = 5%, 0.20 = 20%

stratified_pct_sample <- function(sdf, strat_col, pct, seed = 42L) {
  # sdf_sample returns proportional fractions per stratum
  # Spark's sampleBy needs a named list of fractions per key
  keys <- sdf %>%
    select(!!sym(strat_col)) %>%
    distinct() %>%
    collect() %>%
    pull(1)

  fractions <- setNames(rep(pct, length(keys)), keys)

  sdf %>%
    sdf_sample_by(strat_col, fractions = fractions, seed = seed)
}

sample_pct_sdf <- stratified_pct_sample(pop_keyed, "strat_key", SAMPLE_PCT)

pop_count    <- sdf_nrow(pop_keyed)
sample_count <- sdf_nrow(sample_pct_sdf)
cat(sprintf("\nScenario A – %.0f%% sample\n  Population : %d\n  Sample     : %d (%.2f%%)\n",
            SAMPLE_PCT * 100, pop_count, sample_count,
            sample_count / pop_count * 100))

# ══════════════════════════════════════════════════════════════════
# DISTRIBUTION VALIDATION
# ══════════════════════════════════════════════════════════════════

compare_distributions <- function(pop_sdf, sample_sdf, cols) {
  results <- lapply(cols, function(col) {
    pop_dist <- pop_sdf %>%
      group_by(!!sym(col)) %>%
      summarise(pop_n = n(), .groups = "drop") %>%
      mutate(pop_pct = pop_n / sum(pop_n, na.rm = TRUE)) %>%
      collect()

    samp_dist <- sample_sdf %>%
      group_by(!!sym(col)) %>%
      summarise(samp_n = n(), .groups = "drop") %>%
      mutate(samp_pct = samp_n / sum(samp_n, na.rm = TRUE)) %>%
      collect()

    combined <- full_join(pop_dist, samp_dist, by = col) %>%
      mutate(
        pop_pct  = coalesce(pop_pct,  0),
        samp_pct = coalesce(samp_pct, 0),
        abs_diff = abs(pop_pct - samp_pct)
      ) %>%
      rename(level = !!sym(col)) %>%
      mutate(column = col, level = as.character(level)) %>%
      select(column, level, pop_pct, samp_pct, abs_diff)
    combined
  })
  do.call(rbind, results)
}

validation_df <- compare_distributions(pop_keyed, sample_pct_sdf, CAT_COLS)

cat("\n── Distribution Validation ──\n")
print(validation_df, digits = 4)

cat(sprintf("\nMax absolute drift : %.4f (%.2f%%)\n",
            max(validation_df$abs_diff), max(validation_df$abs_diff) * 100))
cat(sprintf("Mean absolute drift: %.4f (%.2f%%)\n",
            mean(validation_df$abs_diff), mean(validation_df$abs_diff) * 100))

# ── Save outputs ─────────────────────────────────────────────────
spark_write_csv(pop_keyed       %>% select(-strat_key), "population_10k",
                mode = "overwrite")
spark_write_csv(sample_pct_sdf  %>% select(-strat_key), "stratified_sample_pct",
                mode = "overwrite")

write.csv(validation_df, "distribution_validation.csv", row.names = FALSE)
cat("\nFiles saved.\n")

spark_disconnect(sc)
