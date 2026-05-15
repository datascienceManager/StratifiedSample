"""
╔══════════════════════════════════════════════════════════════════════════════╗
║       STRATIFIED SAMPLING — COMPLETE PYTHON SCRIPT (Strategy 1 integrated) ║
║                                                                              ║
║  Schema  : UserID · SportsName · ContentType · Genre · Country · Language   ║
║            TotalMins · TotalCNT                                              ║
║                                                                              ║
║  Strategy: Minimum-Floor Proportional Stratified Sampling                   ║
║    • Stratify on ALL categorical columns simultaneously (composite key)      ║
║    • Scenario A — percentage-based  (e.g. 10%)                              ║
║    • Scenario B — fixed-N per stratum (e.g. 3 rows)                         ║
║    • Small-stratum safeguard: always keep ≥ MIN_ROWS rows per stratum        ║
║      (prevents tiny strata like Iraq / Palestine from disappearing)          ║
║    • Distribution validation — proves sample ≈ population                   ║
║                                                                              ║
║  Reference:                                                                  ║
║    Cochran, W.G. (1977). Sampling Techniques (3rd ed.). Wiley.               ║
║      — Chapter 5: "Stratified Random Sampling"                               ║
║      — Proportional allocation formula: n_h = n × (N_h / N)                 ║
║      — Minimum-floor safeguard: guaranteed ≥1 observation per stratum        ║
║                                                                              ║
║    SAGE Encyclopedia of Educational Research (2018):                         ║
║      "Stratified sampling ensures that at least one observation is picked    ║
║       from each stratum, even if the proportion of population units in a     ║
║       particular stratum is close to 0."                                     ║
║      https://methods.sagepub.com/ency/edvol/                                 ║
║        sage-encyclopedia-of-educational-research-measurement-evaluation/    ║
║        chpt/stratified-random-sampling                                       ║
║                                                                              ║
║  Requires: pandas, numpy                                                     ║
╚══════════════════════════════════════════════════════════════════════════════╝
"""

import pandas as pd
import numpy as np

# ─────────────────────────────────────────────────────────────────
# CONFIGURATION  ← change these values as needed
# ─────────────────────────────────────────────────────────────────
SEED        = 42        # random seed for reproducibility
SAMPLE_PCT  = 0.10      # Scenario A: 10% sample  (try 0.05, 0.20, etc.)
SAMPLE_N    = 3         # Scenario B: 3 rows per stratum (fixed count)
MIN_ROWS    = 1         # Strategy 1 floor — minimum rows per stratum
                        # increase to 2 or 3 if you need richer per-stratum stats

np.random.seed(SEED)


# ══════════════════════════════════════════════════════════════════
# STEP 1 — GENERATE 10K SYNTHETIC DATASET
#           (reflects real schema from image; Iraq & Palestine
#            are intentionally sparse to demonstrate the problem)
# ══════════════════════════════════════════════════════════════════

SPORTS    = ["Football","Tennis","Padel","Motorsports","Basketball","Cricket","Swimming"]
GENRES    = ["Drama","Action","Horror","Comedy","PG","Thriller","Romance"]
LANGUAGES = ["Arabic","English","Turkish","French","Hindi"]

# Imbalanced country distribution: UAE/Qatar/Egypt well represented,
# Iraq (~2.6%) and Palestine (~1.5%) intentionally sparse
COUNTRIES      = ["UAE","Qatar","Egypt","Kuwait","Saudi Arabia","Bahrain","Iraq","Palestine"]
COUNTRY_PROBS  = [ 0.30,  0.25,  0.20,   0.10,         0.07,    0.04,  0.025,     0.015]

USER_IDS = list(range(101, 301))  # 200 unique users

records = []
for _ in range(10_000):
    ct = np.random.choice(["Sports", "Entertainment"], p=[0.45, 0.55])
    records.append({
        "UserID"      : np.random.choice(USER_IDS),
        "ContentType" : ct,
        "SportsName"  : np.random.choice(SPORTS)    if ct == "Sports"        else np.nan,
        "Genre"       : np.random.choice(GENRES)    if ct == "Entertainment" else np.nan,
        "Country"     : np.random.choice(COUNTRIES, p=COUNTRY_PROBS),
        "Language"    : np.random.choice(LANGUAGES, p=[0.35,0.40,0.10,0.08,0.07])
                        if ct == "Entertainment" else np.nan,
        "TotalMins"   : round(float(np.random.exponential(50)), 1),
        "TotalCNT"    : int(np.random.exponential(500)),
    })

df = pd.DataFrame(records)

print("═" * 65)
print("POPULATION OVERVIEW")
print("═" * 65)
print(f"  Rows          : {len(df):,}")
print(f"  Columns       : {list(df.columns)}")
print("\n  Country distribution:")
for country, cnt in df["Country"].value_counts().items():
    bar = "█" * int(cnt / 80)
    print(f"    {country:<15} {cnt:>5}  {bar}")


# ══════════════════════════════════════════════════════════════════
# STEP 2 — BUILD COMPOSITE STRATIFICATION KEY
#           Combines ALL categorical columns into one key.
#           NaN values become "__NA__" so they form their own strata
#           rather than being dropped.
#
#  Example key:  "Sports | __NA__ | Iraq | __NA__ | Football"
#                "Entertainment | Drama | UAE | Arabic | __NA__"
# ══════════════════════════════════════════════════════════════════

CAT_COLS = ["ContentType", "Genre", "Country", "Language", "SportsName"]

df["_strat_key"] = (
    df[CAT_COLS]
    .fillna("__NA__")
    .astype(str)
    .apply(lambda row: " | ".join(row), axis=1)
)

strata_sizes = df.groupby("_strat_key").size().rename("pop_size")

print(f"\n  Total unique strata : {len(strata_sizes):,}")
print(f"  Strata with  1 row  : {(strata_sizes == 1).sum()}")
print(f"  Strata with  2 rows : {(strata_sizes == 2).sum()}")
print(f"  Strata with < 5 rows: {(strata_sizes < 5).sum()}")
print(f"  Strata with <10 rows: {(strata_sizes < 10).sum()}")


# ══════════════════════════════════════════════════════════════════
# STEP 3 — STRATEGY 1: MINIMUM-FLOOR STRATIFIED SAMPLING FUNCTION
#
#  Academic basis:
#    Cochran (1977, Ch.5) — proportional allocation  n_h = n × (N_h / N)
#    SAGE Encyclopedia (2018) — "at least one observation from each stratum"
#
#  Implementation:
#    For each stratum h:
#      target_h = max(MIN_ROWS, round(N_h × pct))   ← floor prevents 0
#      take_h   = min(target_h, N_h)                ← cap prevents over-sampling
#
#  Effect on Iraq / Palestine:
#    Iraq has ~261 rows.  round(261 × 0.10) = 26  → 26 rows sampled  ✓
#    A stratum with 3 rows: round(3 × 0.10) = 0  → floor lifts to 1  ✓
#    A stratum with 1 row:  round(1 × 0.10) = 0  → floor lifts to 1  ✓
# ══════════════════════════════════════════════════════════════════

def stratified_sample_pct(population: pd.DataFrame,
                           strat_col: str,
                           pct: float,
                           min_rows: int = 1,
                           seed: int = SEED) -> pd.DataFrame:
    """
    Percentage-based stratified sample with minimum-floor safeguard.

    Parameters
    ----------
    population : pd.DataFrame
        Full population DataFrame (must contain strat_col).
    strat_col  : str
        Name of the composite stratification key column.
    pct        : float
        Sampling fraction, e.g. 0.10 for 10%.
    min_rows   : int
        Minimum rows to take from any stratum (Strategy 1 floor).
        Default = 1 (no stratum ever disappears completely).
    seed       : int
        Random seed for reproducibility.

    Returns
    -------
    pd.DataFrame  Stratified sample.
    """
    assert 0 < pct < 1, "pct must be between 0 and 1 (exclusive)"
    assert min_rows >= 1, "min_rows must be at least 1"

    parts = []
    floor_applied = 0   # count how many strata needed the floor

    for key, group in population.groupby(strat_col):
        n_target = round(len(group) * pct)

        if n_target < min_rows:
            n_target = min_rows          # ← Strategy 1: apply floor
            floor_applied += 1

        n_take = min(n_target, len(group))  # never exceed available rows
        parts.append(group.sample(n=n_take, random_state=seed))

    sample = pd.concat(parts).reset_index(drop=True)

    print(f"\n  [stratified_sample_pct] floor applied to {floor_applied} strata "
          f"(would have been 0 rows at {pct*100:.0f}%)")
    return sample


def stratified_sample_n(population: pd.DataFrame,
                        strat_col: str,
                        n_per_stratum: int,
                        seed: int = SEED) -> pd.DataFrame:
    """
    Fixed-N stratified sample with cap safeguard.

    Parameters
    ----------
    population    : pd.DataFrame
    strat_col     : str
    n_per_stratum : int
        Exact rows to draw from each stratum.
        If a stratum has fewer rows than n_per_stratum, all its rows are taken.
    seed          : int

    Returns
    -------
    pd.DataFrame  Stratified sample.
    """
    assert n_per_stratum >= 1, "n_per_stratum must be at least 1"

    parts = []
    capped = 0

    for key, group in population.groupby(strat_col):
        n_take = min(n_per_stratum, len(group))   # cap if stratum is tiny
        if n_take < n_per_stratum:
            capped += 1
        parts.append(group.sample(n=n_take, random_state=seed))

    sample = pd.concat(parts).reset_index(drop=True)

    print(f"\n  [stratified_sample_n] {capped} strata capped "
          f"(had fewer than {n_per_stratum} rows)")
    return sample


# ══════════════════════════════════════════════════════════════════
# STEP 4 — RUN BOTH SCENARIOS
# ══════════════════════════════════════════════════════════════════

print("\n" + "═" * 65)
print("SCENARIO A — PERCENTAGE-BASED SAMPLE  ({:.0f}%)".format(SAMPLE_PCT * 100))
print("═" * 65)
sample_pct = stratified_sample_pct(df, "_strat_key", SAMPLE_PCT, min_rows=MIN_ROWS)
print(f"  Population : {len(df):,} rows")
print(f"  Sample     : {len(sample_pct):,} rows  "
      f"({len(sample_pct)/len(df)*100:.2f}% of population)")

# Verify Iraq / Palestine are preserved
for country in ["Iraq", "Palestine"]:
    pop_n  = df["Country"].value_counts().get(country, 0)
    samp_n = sample_pct["Country"].value_counts().get(country, 0)
    pct_kept = (samp_n / pop_n * 100) if pop_n > 0 else 0
    print(f"  {country:<15} — population: {pop_n:>4} | sample: {samp_n:>3} "
          f"({pct_kept:.1f}% represented)")


print("\n" + "═" * 65)
print("SCENARIO B — FIXED-N SAMPLE  ({} rows per stratum)".format(SAMPLE_N))
print("═" * 65)
sample_n = stratified_sample_n(df, "_strat_key", SAMPLE_N)
print(f"  Population : {len(df):,} rows")
print(f"  Sample     : {len(sample_n):,} rows")

for country in ["Iraq", "Palestine"]:
    pop_n  = df["Country"].value_counts().get(country, 0)
    samp_n = sample_n["Country"].value_counts().get(country, 0)
    print(f"  {country:<15} — population: {pop_n:>4} | sample: {samp_n:>3}")


# ══════════════════════════════════════════════════════════════════
# STEP 5 — DISTRIBUTION VALIDATION
#           Compare population % vs sample % for every categorical
#           column individually.  Max drift < 5% = good.
# ══════════════════════════════════════════════════════════════════

def validate_distributions(population: pd.DataFrame,
                            sample: pd.DataFrame,
                            cols: list) -> pd.DataFrame:
    """
    For each categorical column, compute the absolute percentage difference
    between population distribution and sample distribution.

    Returns a tidy DataFrame with columns:
        column | level | pop_pct | sample_pct | abs_diff_pct | status
    """
    rows = []
    for col in cols:
        pop_dist    = (population[col].fillna("__NA__")
                       .value_counts(normalize=True)
                       .rename("pop_pct"))
        sample_dist = (sample[col].fillna("__NA__")
                       .value_counts(normalize=True)
                       .rename("sample_pct"))
        combined = (pd.concat([pop_dist, sample_dist], axis=1)
                    .fillna(0)
                    .reset_index()
                    .rename(columns={"index": "level"}))
        combined.columns = ["level", "pop_pct", "sample_pct"]
        combined["abs_diff_pct"] = (
            (combined["pop_pct"] - combined["sample_pct"]).abs() * 100
        ).round(2)
        combined["status"] = combined["abs_diff_pct"].apply(
            lambda x: "✓ OK" if x < 5.0 else "⚠ DRIFT"
        )
        combined.insert(0, "column", col)
        rows.append(combined)
    return pd.concat(rows, ignore_index=True)


print("\n" + "═" * 65)
print("DISTRIBUTION VALIDATION — Scenario A ({}% sample)".format(int(SAMPLE_PCT*100)))
print("═" * 65)

validation = validate_distributions(df, sample_pct, CAT_COLS)

pd.set_option("display.float_format", "{:.4f}".format)
pd.set_option("display.max_rows", 60)
pd.set_option("display.width", 120)
print(validation.to_string(index=False))

max_drift  = validation["abs_diff_pct"].max()
mean_drift = validation["abs_diff_pct"].mean()
n_drifted  = (validation["abs_diff_pct"] >= 5.0).sum()

print(f"\n  Max absolute drift : {max_drift:.2f}%")
print(f"  Mean absolute drift: {mean_drift:.2f}%")
print(f"  Levels with drift ≥ 5%: {n_drifted}")
print(f"\n  {'✅ PASS — sample is representative.' if max_drift < 5 else '⚠ REVIEW — some levels show >5% drift.'}")


# ══════════════════════════════════════════════════════════════════
# STEP 6 — SAVE OUTPUTS
# ══════════════════════════════════════════════════════════════════

# Drop internal key column before saving
df_out         = df.drop(columns=["_strat_key"])
sample_pct_out = sample_pct.drop(columns=["_strat_key"])
sample_n_out   = sample_n.drop(columns=["_strat_key"])

df_out.to_csv("population_10k.csv",            index=False)
sample_pct_out.to_csv("sample_pct_10pct.csv",  index=False)
sample_n_out.to_csv("sample_fixed_n.csv",      index=False)
validation.to_csv("distribution_validation.csv", index=False)

print("\n" + "═" * 65)
print("FILES SAVED")
print("═" * 65)
print("  population_10k.csv          — full 10K population")
print("  sample_pct_10pct.csv        — Scenario A: 10% stratified sample")
print("  sample_fixed_n.csv          — Scenario B: fixed-N stratified sample")
print("  distribution_validation.csv — drift report")
