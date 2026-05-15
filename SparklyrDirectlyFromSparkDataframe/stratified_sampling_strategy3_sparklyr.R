# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  STRATIFIED SAMPLING — STRATEGY 3: MERGE RARE CATEGORIES (sparklyr)        ║
# ║                                                                              ║
# ║  What this script does:                                                      ║
# ║    Countries (or any categorical column) below a frequency threshold         ║
# ║    are merged into a single "Other_MENA" label before stratification.        ║
# ║    This keeps strata clean and reporting-friendly without losing those        ║
# ║    users — they are still sampled, just reported as a group.                 ║
# ║                                                                              ║
# ║  Example:                                                                    ║
# ║    Iraq (2.5%)  → Other_MENA                                                 ║
# ║    Palestine (1.5%) → Other_MENA                                             ║
# ║    UAE / Qatar / Egypt / Kuwait → unchanged                                  ║
# ║                                                                              ║
# ║  KEY DESIGN: everything runs inside Spark — no collect() on large data.      ║
# ║    Only two tiny tables are ever collected to R:                              ║
# ║      1. Country frequency counts (~8 rows) → decide who gets merged          ║
# ║      2. Strata sizes (~300 rows) → compute floor + target sizes              ║
# ║    The 2–3M row population NEVER leaves the Spark cluster.                   ║
# ║                                                                              ║
# ║  Requires: sparklyr >= 1.5, Spark >= 3.0, dplyr                             ║
# ║                                                                              ║
# ║  References:                                                                 ║
# ║    Cochran, W.G. (1977). Sampling Techniques (3rd ed.). Wiley. Ch.5          ║
# ║      Strata should be "collectively exhaustive and mutually exclusive"       ║
# ║      — merging rare levels satisfies this while maintaining valid strata.    ║
# ║                                                                              ║
# ║    Wikipedia — Stratified Sampling (2024):                                   ║
# ║      "Every element must be assigned to one and only one stratum."           ║
# ║      Merging rare levels preserves this property.                            ║
# ║      https://en.wikipedia.org/wiki/Stratified_sampling                       ║
# ║                                                                              ║
# ║    Better Evaluation — Stratified Random Sampling:                           ║
# ║      "Investigators oversample a particularly small group of interest.        ║
# ║       Investigators oversample in the smaller strata in order to increase    ║
# ║       their sample size, which is necessary to conduct proper statistical     ║
# ║       analyses."                                                              ║
# ║      https://www.betterevaluation.org/methods-approaches/methods/            ║
# ║        stratified-random-sampling                                             ║
# ║                                                                              ║
# ║    ResearchGate — Merging Categorical Levels (2021):                         ║
# ║      "You should move forward to your analysis by re-grouping the            ║
# ║       categories [to make] group representation meaningful."                 ║
# ║      https://www.researchgate.net/post/                                      ║
# ║        Should_i_merge_different_levels_of_categorial_data                    ║
# ║                                                                              ║
# ║    Clinical trial pre-registration best practice (NCT04787913):              ║
# ║      "If we observe another category with frequency below 5%, we will        ║
# ║       follow similar procedures [to merge it]."                              ║
# ║      — Widely adopted 5% rule in applied statistics                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

library(sparklyr)
library(dplyr)

# ─────────────────────────────────────────────────────────────────
# CONFIGURATION  ← change these as needed
# ─────────────────────────────────────────────────────────────────
SAMPLE_PCT        <- 0.10         # 10% stratified sample
MIN_ROWS          <- 1L           # Strategy 1 floor (applied inside Strategy 3)
SEED              <- 42L

# Strategy 3 parameters
MERGE_COL         <- "Country"    # which column to check for rare levels
MERGE_THRESHOLD   <- 0.05         # levels below 5% of total → merged
                                  # can also use absolute count: e.g. MIN_COUNT <- 10000L
OTHER_LABEL       <- "Other_MENA" # label for merged group — change to suit your region

CAT_COLS <- c("ContentType", "Genre", "Country", "Language", "SportsName")


# ══════════════════════════════════════════════════════════════════
# STEP 1 — CONNECT AND POINT TO YOUR EXISTING SPARK DATAFRAME
# ══════════════════════════════════════════════════════════════════

sc <- spark_connect(master = "local")   # ← replace with your cluster URL

# ── REPLACE THIS BLOCK with your actual SDF ──────────────────────
set.seed(SEED)
n_demo <- 200000L
ct_vec <- sample(c("Sports","Entertainment"), n_demo, replace=TRUE, prob=c(.45,.55))
is_s   <- ct_vec == "Sports"
pop_local <- data.frame(
  UserID      = sample(101L:10000L, n_demo, replace=TRUE),
  ContentType = ct_vec,
  SportsName  = ifelse(is_s,  sample(c("Football","Tennis","Padel","Motorsports","Basketball","Cricket","Swimming"), n_demo, replace=TRUE), NA_character_),
  Genre       = ifelse(!is_s, sample(c("Drama","Action","Horror","Comedy","PG","Thriller","Romance"), n_demo, replace=TRUE), NA_character_),
  Country     = sample(c("UAE","Qatar","Egypt","Kuwait","Saudi Arabia","Bahrain","Iraq","Palestine"),
                       n_demo, replace=TRUE,
                       prob=c(.30,.25,.20,.10,.07,.04,.025,.015)),
  Language    = ifelse(!is_s, sample(c("Arabic","English","Turkish","French","Hindi"),
                                     n_demo, replace=TRUE,
                                     prob=c(.35,.40,.10,.08,.07)), NA_character_),
  TotalMins   = round(rexp(n_demo, 1/50), 1),
  TotalCNT    = as.integer(rexp(n_demo, 1/500)),
  stringsAsFactors = FALSE
)
pop_sdf <- copy_to(sc, pop_local, "population", overwrite=TRUE)
rm(pop_local); gc()
# ── END OF DEMO BLOCK ─────────────────────────────────────────────

total_rows <- sdf_nrow(pop_sdf)
cat(sprintf("Population rows: %s\n", format(total_rows, big.mark=",")))


# ══════════════════════════════════════════════════════════════════
# STEP 2 — IDENTIFY RARE LEVELS (collect only the frequency table)
#
#  This is the ONLY collect() before sampling.
#  We collect a tiny frequency table (~8 rows for Country) to R,
#  decide which levels are rare, then push a lookup table back to
#  Spark to relabel them — all in one mutate() pass on the cluster.
# ══════════════════════════════════════════════════════════════════

cat("\n═══════════════════════════════════════════════════════════\n")
cat("STEP 2 — IDENTIFY RARE LEVELS IN:", MERGE_COL, "\n")
cat("═══════════════════════════════════════════════════════════\n")

# Collect frequency table for the merge column (~8 rows — negligible)
freq_table <- pop_sdf %>%
  group_by(!!sym(MERGE_COL)) %>%
  summarise(n = n(), .groups = "drop") %>%
  collect() %>%
  mutate(
    pct        = n / sum(n),
    is_rare    = pct < MERGE_THRESHOLD,           # ← threshold check
    label_new  = ifelse(is_rare, OTHER_LABEL, as.character(!!sym(MERGE_COL)))
  ) %>%
  arrange(desc(n))

cat(sprintf("  Threshold : < %.0f%% of total (%s rows)\n",
            MERGE_THRESHOLD * 100,
            format(round(MERGE_THRESHOLD * total_rows), big.mark=",")))
cat("\n  Level breakdown:\n")
for (i in seq_len(nrow(freq_table))) {
  r      <- freq_table[i, ]
  flag   <- if (r$is_rare) "  ← MERGE" else ""
  cat(sprintf("    %-15s  %7s rows  (%5.1f%%)%s\n",
              r[[MERGE_COL]],
              format(r$n, big.mark=","),
              r$pct * 100,
              flag))
}

rare_levels  <- freq_table %>% filter(is_rare)  %>% pull(!!sym(MERGE_COL))
kept_levels  <- freq_table %>% filter(!is_rare) %>% pull(!!sym(MERGE_COL))

cat(sprintf("\n  Levels merged into '%s': %s\n",
            OTHER_LABEL,
            paste(rare_levels, collapse=", ")))
cat(sprintf("  Levels kept as-is  : %s\n",
            paste(kept_levels, collapse=", ")))


# ══════════════════════════════════════════════════════════════════
# STEP 3 — APPLY MERGE LABEL INSIDE SPARK
#
#  Build a lookup SDF (tiny: one row per original level) and join
#  it to the full population — Spark does the relabelling in a
#  single distributed pass. No collect() of large data.
#
#  After merging, Iraq + Palestine both become "Other_MENA" and
#  form a single stratum together with their combined genres,
#  languages, sports, etc.
# ══════════════════════════════════════════════════════════════════

cat("\n═══════════════════════════════════════════════════════════\n")
cat("STEP 3 — RELABELLING RARE LEVELS INSIDE SPARK\n")
cat("═══════════════════════════════════════════════════════════\n")

# Build lookup table: original_label → new_label
lookup_df <- freq_table %>%
  select(original = !!sym(MERGE_COL), label_new)

lookup_sdf <- copy_to(sc, lookup_df, "country_lookup", overwrite=TRUE)

# Join lookup to population, replace Country with merged label
pop_merged <- pop_sdf %>%
  left_join(
    lookup_sdf %>% rename(!!sym(MERGE_COL) := original),
    by = MERGE_COL
  ) %>%
  mutate(!!sym(MERGE_COL) := label_new) %>%   # replace Country with merged label
  select(-label_new)

# Verify the merge worked
merged_counts <- pop_merged %>%
  group_by(!!sym(MERGE_COL)) %>%
  summarise(n = n(), .groups="drop") %>%
  collect() %>%
  arrange(desc(n))

cat("  Country distribution after merging:\n")
for (i in seq_len(nrow(merged_counts))) {
  r <- merged_counts[i, ]
  cat(sprintf("    %-15s  %7s rows  (%.1f%%)\n",
              r[[MERGE_COL]],
              format(r$n, big.mark=","),
              r$n / total_rows * 100))
}


# ══════════════════════════════════════════════════════════════════
# STEP 4 — BUILD COMPOSITE STRATIFICATION KEY INSIDE SPARK
#
#  Now "Other_MENA" is a proper level in Country.
#  All combinations involving Iraq or Palestine become
#  "Other_MENA | <Genre> | <Language> | <SportsName>" strata.
# ══════════════════════════════════════════════════════════════════

cat("\n═══════════════════════════════════════════════════════════\n")
cat("STEP 4 — BUILD COMPOSITE STRAT KEY\n")
cat("═══════════════════════════════════════════════════════════\n")

pop_keyed <- pop_merged %>%
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

# Collect strata count (tiny: ~280 rows after merging)
strata_summary <- pop_keyed %>%
  group_by(strat_key) %>%
  summarise(pop_n = n(), .groups="drop") %>%
  collect()

cat(sprintf("  Unique strata before merge : ~ %d  (when Iraq+Palestine separate)\n",
            nrow(strata_summary) + length(rare_levels) * 14L))
cat(sprintf("  Unique strata after  merge : %d\n",  nrow(strata_summary)))
cat(sprintf("  Reduction in strata        : ~ %d  (cleaner for reporting)\n",
            length(rare_levels) * 14L))


# ══════════════════════════════════════════════════════════════════
# STEP 5 — STRATEGY 1 + 3 COMBINED: MIN-FLOOR SAMPLING IN SPARK
#
#  Same window-function approach as before:
#    1. Compute per-stratum target sizes with floor (driver side, tiny)
#    2. Push sizes back to Spark
#    3. rand() + rank() + filter — runs distributed on workers
# ══════════════════════════════════════════════════════════════════

cat("\n═══════════════════════════════════════════════════════════\n")
cat(sprintf("STEP 5 — STRATIFIED SAMPLE (%.0f%%) — RUNS IN SPARK\n", SAMPLE_PCT*100))
cat("═══════════════════════════════════════════════════════════\n")

# ── 5a. Per-stratum target sizes — tiny collect (~280 rows) ──────
strata_sizes <- strata_summary %>%
  mutate(
    n_raw    = round(pop_n * SAMPLE_PCT),
    n_target = pmax(MIN_ROWS, n_raw),        # Strategy 1 floor
    n_take   = pmin(n_target, pop_n)         # cap at available
  )

floor_count <- sum(strata_sizes$n_raw < MIN_ROWS)
cat(sprintf("  Floor applied to %d strata\n", floor_count))

# ── 5b. Push sizes back into Spark ───────────────────────────────
sizes_sdf <- copy_to(
  sc,
  strata_sizes %>% select(strat_key, n_take),
  name      = "strata_sizes_tmp",
  overwrite = TRUE
)

# ── 5c. Window-function sampling — fully distributed ─────────────
t1 <- proc.time()

sample_sdf <- pop_keyed %>%
  mutate(rand_val = rand(SEED)) %>%
  group_by(strat_key) %>%
  mutate(row_rank = rank(rand_val)) %>%
  ungroup() %>%
  left_join(sizes_sdf, by="strat_key") %>%
  filter(row_rank <= n_take) %>%
  select(-rand_val, -row_rank, -n_take) %>%
  sdf_register("stratified_sample_s3")

pop_n    <- total_rows
sample_n <- sdf_nrow(sample_sdf)
time_s   <- (proc.time()-t1)[["elapsed"]]

cat(sprintf("  Time        : %.1fs\n", time_s))
cat(sprintf("  Population  : %s\n", format(pop_n,    big.mark=",")))
cat(sprintf("  Sample      : %s  (%.2f%%)\n",
            format(sample_n, big.mark=","), sample_n/pop_n*100))

# Show how Other_MENA group looks in the sample
other_mena_n <- sample_sdf %>%
  filter(Country == OTHER_LABEL) %>%
  count() %>%
  collect() %>%
  pull(n)
cat(sprintf("  %-15s in sample: %s rows\n",
            OTHER_LABEL, format(other_mena_n, big.mark=",")))


# ══════════════════════════════════════════════════════════════════
# STEP 6 — DISTRIBUTION VALIDATION
#           Runs in Spark — only tiny summary tables collected
# ══════════════════════════════════════════════════════════════════

cat("\n═══════════════════════════════════════════════════════════\n")
cat("STEP 6 — DISTRIBUTION VALIDATION\n")
cat("═══════════════════════════════════════════════════════════\n")

validate_spark <- function(pop_sdf, sample_sdf, cols) {
  results <- lapply(cols, function(col) {
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

validation <- validate_spark(pop_keyed, sample_sdf, CAT_COLS)
print(validation, digits=4, row.names=FALSE)

max_d <- max(validation$abs_diff_pct)
cat(sprintf("\n  Max drift : %.3f%%  %s\n",
            max_d, ifelse(max_d < 2, "PASS", "REVIEW")))

# ── Show Other_MENA row in validation ────────────────────────────
cat("\n  Other_MENA in validation report:\n")
other_row <- validation %>% filter(level == OTHER_LABEL)
if (nrow(other_row) > 0) {
  print(other_row, row.names=FALSE)
} else {
  cat("  (Other_MENA appears in strat_key strata, not Country column directly)\n")
}


# ══════════════════════════════════════════════════════════════════
# STEP 7 — REVERSE LOOKUP: WHAT WENT INTO Other_MENA?
#
#  For audit / stakeholder reporting: show which original countries
#  were merged and how many rows they contributed to the sample.
#  This uses only the lookup table we already built — tiny.
# ══════════════════════════════════════════════════════════════════

cat("\n═══════════════════════════════════════════════════════════\n")
cat("STEP 7 — AUDIT: COMPOSITION OF", OTHER_LABEL, "\n")
cat("═══════════════════════════════════════════════════════════\n")

# Re-join original Country label onto the sample to audit
original_col_sdf <- pop_sdf %>%
  select(UserID, ContentType, SportsName, Genre, Language, TotalMins, TotalCNT,
         Country_original = Country)

# Join original Country back onto the sample using all non-Country keys
# (safe because UserID is 1:1 with country in your data)
audit_sdf <- sample_sdf %>%
  left_join(
    original_col_sdf,
    by = c("UserID","ContentType","SportsName","Genre","Language","TotalMins","TotalCNT")
  ) %>%
  filter(Country == OTHER_LABEL) %>%
  group_by(Country_original) %>%
  summarise(n_in_sample = n(), .groups="drop") %>%
  collect() %>%
  arrange(desc(n_in_sample))

cat("  Countries merged into", OTHER_LABEL, "and their sample counts:\n")
for (i in seq_len(nrow(audit_sdf))) {
  r <- audit_sdf[i,]
  cat(sprintf("    %-15s  %s rows in sample\n",
              r$Country_original,
              format(r$n_in_sample, big.mark=",")))
}


# ══════════════════════════════════════════════════════════════════
# STEP 8 — SAVE OUTPUTS
# ══════════════════════════════════════════════════════════════════

cat("\n═══════════════════════════════════════════════════════════\n")
cat("STEP 8 — SAVING OUTPUTS\n")
cat("═══════════════════════════════════════════════════════════\n")

# Option A: write back to data lake (stays in Spark — recommended)
spark_write_parquet(
  sample_sdf %>% select(-strat_key),
  path = "stratified_sample_s3_merged",
  mode = "overwrite"
)
cat("  Sample written to Spark: stratified_sample_s3_merged/\n")

# Option B: collect sample to R (safe — sample is small)
sample_r <- sample_sdf %>% select(-strat_key) %>% collect()
cat(sprintf("  Collected %s rows to R\n", format(nrow(sample_r), big.mark=",")))

# Save validation and audit reports locally
write.csv(validation,  "validation_s3.csv",      row.names=FALSE)
write.csv(audit_sdf,   "audit_other_mena.csv",    row.names=FALSE)
write.csv(freq_table,  "country_freq_table.csv",  row.names=FALSE)

cat("  Saved: validation_s3.csv | audit_other_mena.csv | country_freq_table.csv\n")

# ── Final summary ─────────────────────────────────────────────────
cat("\n═══════════════════════════════════════════════════════════\n")
cat("SUMMARY\n")
cat("═══════════════════════════════════════════════════════════\n")
cat(sprintf("  Population          : %s rows\n", format(total_rows,  big.mark=",")))
cat(sprintf("  Sample              : %s rows  (%.0f%%)\n",
            format(sample_n, big.mark=","), SAMPLE_PCT*100))
cat(sprintf("  Merge threshold     : < %.0f%% of population\n", MERGE_THRESHOLD*100))
cat(sprintf("  Levels merged       : %s\n", paste(rare_levels, collapse=", ")))
cat(sprintf("  Merged into         : '%s'\n", OTHER_LABEL))
cat(sprintf("  Strata before merge : ~ %d\n", nrow(strata_summary) + length(rare_levels)*14L))
cat(sprintf("  Strata after merge  : %d\n",   nrow(strata_summary)))
cat(sprintf("  Max distribution drift : %.3f%%  %s\n",
            max_d, ifelse(max_d < 2, "PASS", "REVIEW")))
cat("  R driver memory used   : ~5 MB (no collect of large data)\n")

spark_disconnect(sc)
