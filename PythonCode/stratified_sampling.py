"""
Stratified Sampling Script
==========================
1. Generate a 10K synthetic dataset based on the sample schema
2. Scenario A – Percentage-based stratified sample
3. Validate distribution similarity between population and sample
"""

import pandas as pd
import numpy as np
from collections import defaultdict

# ─────────────────────────────────────────────
# 0. Reproducibility
# ─────────────────────────────────────────────
SEED = 42
np.random.seed(SEED)

# ─────────────────────────────────────────────
# 1. GENERATE SYNTHETIC 10K DATASET
# ─────────────────────────────────────────────
N = 10_000

# Domain values derived from the sample image
SPORTS = ["Football", "Tennis", "Padel", "Motorsports", "Basketball", "Cricket", "Swimming"]
ENTERTAINMENT_GENRES = ["Drama", "Action", "Horror", "Comedy", "PG", "Thriller", "Romance"]
COUNTRIES = ["UAE", "Qatar", "Egypt", "Kuwait", "Saudi Arabia", "Bahrain", "Jordan"]
LANGUAGES = ["Arabic", "English", "Turkish", "French", "Hindi"]
USER_IDS = list(range(101, 201))          # 100 users

records = []
for i in range(N):
    user_id = np.random.choice(USER_IDS)
    country = np.random.choice(COUNTRIES, p=[0.25, 0.20, 0.18, 0.12, 0.12, 0.07, 0.06])
    content_type = np.random.choice(["Sports", "Entertainment"], p=[0.45, 0.55])

    if content_type == "Sports":
        sport_name = np.random.choice(SPORTS)
        genre = np.nan
        language = np.nan
    else:
        sport_name = np.nan
        genre = np.random.choice(ENTERTAINMENT_GENRES)
        language = np.random.choice(LANGUAGES, p=[0.35, 0.40, 0.10, 0.08, 0.07])

    total_mins = round(np.random.exponential(scale=50), 1)
    total_cnt  = int(np.random.exponential(scale=500))

    records.append({
        "UserID":      user_id,
        "SportsName":  sport_name,
        "ContentType": content_type,
        "Genre":       genre,
        "Country":     country,
        "Language":    language,
        "TotalMins":   total_mins,
        "TotalCNT":    total_cnt,
    })

df = pd.DataFrame(records)
print(f"Dataset shape: {df.shape}")
print(df.head(5).to_string())
print("\nContentType distribution:\n", df["ContentType"].value_counts())

# ─────────────────────────────────────────────
# 2. HELPER – STRATIFICATION KEY
#    Combines ALL categorical columns into one
#    composite key so every unique combination
#    is treated as its own stratum.
# ─────────────────────────────────────────────
CAT_COLS = ["ContentType", "Genre", "Country", "Language", "SportsName"]

def build_strat_key(frame: pd.DataFrame, cols: list) -> pd.Series:
    """Return a single string column = concatenation of all categorical values."""
    filled = frame[cols].fillna("__NA__").astype(str)
    return filled.apply(lambda row: " | ".join(row), axis=1)

df["_strat_key"] = build_strat_key(df, CAT_COLS)

print(f"\nNumber of unique strata: {df['_strat_key'].nunique()}")

# ─────────────────────────────────────────────
# 3. SCENARIO A – PERCENTAGE-BASED STRATIFIED SAMPLE
#    Usage: set SAMPLE_PCT to whatever fraction you need
# ─────────────────────────────────────────────
SAMPLE_PCT = 0.10   # <── Change this: e.g. 0.05 = 5%, 0.20 = 20%

def stratified_sample_pct(
    population: pd.DataFrame,
    strat_col: str,
    pct: float,
    seed: int = SEED,
    min_per_stratum: int = 1,
) -> pd.DataFrame:
    """
    Draw `pct` fraction from each stratum.
    Strata smaller than 1/pct rows still yield at least `min_per_stratum` row(s).
    """
    assert 0 < pct < 1, "pct must be between 0 and 1 (exclusive)"
    parts = []
    for _, group in population.groupby(strat_col):
        n = max(min_per_stratum, round(len(group) * pct))
        n = min(n, len(group))          # can't sample more than available
        parts.append(group.sample(n=n, random_state=seed))
    return pd.concat(parts).reset_index(drop=True)

sample_pct = stratified_sample_pct(df, "_strat_key", SAMPLE_PCT)
print(f"\n── Scenario A ({SAMPLE_PCT*100:.0f}% sample) ──")
print(f"Population : {len(df):,} rows")
print(f"Sample     : {len(sample_pct):,} rows  ({len(sample_pct)/len(df)*100:.2f}% of pop)")

# ─────────────────────────────────────────────
# 4. DISTRIBUTION VALIDATION
#    Compare population vs sample for every
#    categorical column individually.
# ─────────────────────────────────────────────

def compare_distributions(
    population: pd.DataFrame,
    sample: pd.DataFrame,
    cols: list,
) -> pd.DataFrame:
    """
    Returns a DataFrame with pop_pct, sample_pct, and absolute difference
    for every level of every categorical column.
    """
    rows = []
    for col in cols:
        pop_dist    = population[col].fillna("__NA__").value_counts(normalize=True).rename("pop_pct")
        sample_dist = sample[col].fillna("__NA__").value_counts(normalize=True).rename("sample_pct")
        combined    = pd.concat([pop_dist, sample_dist], axis=1).fillna(0)
        combined["abs_diff"] = (combined["pop_pct"] - combined["sample_pct"]).abs()
        combined.index.name  = "level"
        combined              = combined.reset_index()
        combined.insert(0, "column", col)
        rows.append(combined)
    return pd.concat(rows, ignore_index=True)

validation = compare_distributions(df, sample_pct, CAT_COLS)

print("\n── Distribution Validation (population vs stratified sample) ──")
pd.set_option("display.float_format", "{:.4f}".format)
print(validation.to_string(index=False))

max_drift = validation["abs_diff"].max()
avg_drift = validation["abs_diff"].mean()
print(f"\nMax absolute drift : {max_drift:.4f}  ({max_drift*100:.2f}%)")
print(f"Mean absolute drift: {avg_drift:.4f}  ({avg_drift*100:.2f}%)")

# ─────────────────────────────────────────────
# 5. SAVE OUTPUTS
# ─────────────────────────────────────────────
df.drop(columns=["_strat_key"]).to_csv("population_10k.csv", index=False)
sample_pct.drop(columns=["_strat_key"]).to_csv("stratified_sample_pct.csv", index=False)
validation.to_csv("distribution_validation.csv", index=False)
print("\nFiles saved: population_10k.csv | stratified_sample_pct.csv | distribution_validation.csv")
