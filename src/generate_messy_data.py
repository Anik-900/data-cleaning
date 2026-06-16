"""
generate_messy_data.py
----------------------
Creates a synthetic, deterministic marketing-campaign dataset that contains
real-world data quality issues. The output CSV is written to:

    data/raw/marketing_campaign_messy.csv

This script exists so that the entire cleaning project is fully reproducible:
anyone can clone the repo and regenerate the exact same "messy" input the
cleaning pipeline expects.

Issues intentionally introduced
-------------------------------
- Negative values in Spend, CPC, and Cost_Per_Conversion
- Extreme outliers in Spend (a handful of huge values such as 500,000)
- Missing values across multiple columns at realistic rates
- Invalid date ordering (Start_Date > End_Date) for some rows
- Inconsistent types (Active stored as 'Yes'/'No', Conversions stored as float)
- Outdated derived columns (CTR / CPC / Conversion_Rate / Cost_Per_Conversion)
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SEED = 42
N_ROWS = 2000
CHANNELS = ["Facebook", "Google Ads", "TikTok", "Email", "Instagram"]
CAMPAIGN_PREFIXES = ["Q1_Launch", "Q2_Winter", "Q3_Winter", "Q4_Summer", "Q1_BlackFriday"]

OUTPUT_PATH = Path(__file__).resolve().parents[1] / "data" / "raw" / "marketing_campaign_messy.csv"


def generate() -> pd.DataFrame:
    """Build the messy DataFrame deterministically."""
    rng = np.random.default_rng(SEED)

    # --- Campaign IDs and names -------------------------------------------------
    campaign_ids = [f"CMP-{i:05d}" for i in range(1, N_ROWS + 1)]
    campaign_names = [
        f"{rng.choice(CAMPAIGN_PREFIXES)}_{cid}" for cid in campaign_ids
    ]

    # --- Dates ------------------------------------------------------------------
    base = pd.Timestamp("2023-01-01")
    start_offsets = rng.integers(0, 365, size=N_ROWS)
    duration_days = rng.integers(1, 30, size=N_ROWS)
    start_dates = [base + pd.Timedelta(days=int(d)) for d in start_offsets]
    end_dates = [s + pd.Timedelta(days=int(dur)) for s, dur in zip(start_dates, duration_days)]

    # --- Core metrics -----------------------------------------------------------
    impressions = rng.integers(500, 100_000, size=N_ROWS)
    clicks = (impressions * rng.uniform(0.005, 0.05, size=N_ROWS)).astype(int)
    clicks = np.clip(clicks, 1, None)  # never zero, to keep CPC defined
    spend = np.round(clicks * rng.uniform(0.3, 2.0, size=N_ROWS), 2)
    conversions = (clicks * rng.uniform(0.01, 0.20, size=N_ROWS)).astype(float)
    conversions = np.clip(conversions, 0, None)
    active = rng.choice(["Yes", "No"], size=N_ROWS, p=[0.6, 0.4])

    df = pd.DataFrame({
        "Campaign_ID": campaign_ids,
        "Campaign_Name": campaign_names,
        "Start_Date": [d.strftime("%Y-%m-%d") for d in start_dates],
        "End_Date": [d.strftime("%Y-%m-%d") for d in end_dates],
        "Channel": rng.choice(CHANNELS, size=N_ROWS),
        "Impressions": impressions,
        "Clicks": clicks,
        "Spend": spend,
        "Conversions": conversions,
        "Active": active,
    })

    # Derived columns (initially correct, will be partially broken by issues below)
    df["CTR"] = np.round(df["Clicks"] / df["Impressions"] * 100, 2)
    df["CPC"] = np.round(df["Spend"] / df["Clicks"], 2)
    df["Conversion_Rate"] = np.round(
        np.where(df["Clicks"] > 0, df["Conversions"] / df["Clicks"] * 100, 0), 2
    )
    df["Cost_Per_Conversion"] = np.where(
        df["Conversions"] > 0,
        np.round(df["Spend"] / df["Conversions"], 2),
        np.nan,
    )

    # ---------------------------------------------------------------------------
    # Inject data quality issues
    # ---------------------------------------------------------------------------

    # 1. Negative values in Spend / CPC / Cost_Per_Conversion (~19 each)
    neg_idx_spend = rng.choice(N_ROWS, size=19, replace=False)
    df.loc[neg_idx_spend, "Spend"] *= -1
    df.loc[neg_idx_spend, "CPC"] *= -1
    df.loc[neg_idx_spend, "Cost_Per_Conversion"] *= -1

    # 2. Extreme outliers in Spend (a few rows pushed to absurd values)
    outlier_idx = rng.choice(N_ROWS, size=5, replace=False)
    df.loc[outlier_idx, "Spend"] = 500_000.0
    df.loc[outlier_idx, "CPC"] = df.loc[outlier_idx, "Spend"] / df.loc[outlier_idx, "Clicks"]

    # 3. Missing values
    def _set_nan(column: str, frac: float) -> None:
        idx = rng.choice(N_ROWS, size=int(N_ROWS * frac), replace=False)
        df.loc[idx, column] = np.nan

    _set_nan("Channel", 0.05)
    _set_nan("Spend", 0.147)
    _set_nan("Conversions", 0.10)
    _set_nan("CPC", 0.147)
    _set_nan("Conversion_Rate", 0.10)
    _set_nan("Cost_Per_Conversion", 0.2315)

    # 4. Invalid date ordering (~78 rows where Start_Date > End_Date)
    swap_idx = rng.choice(N_ROWS, size=78, replace=False)
    df.loc[swap_idx, ["Start_Date", "End_Date"]] = df.loc[
        swap_idx, ["End_Date", "Start_Date"]
    ].values

    return df


def main() -> None:
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    df = generate()
    df.to_csv(OUTPUT_PATH, index=False)
    print(f"Wrote {len(df):,} rows to {OUTPUT_PATH}")
    print("Issues injected:")
    print(f"  - Rows with negative Spend       : {(df['Spend'] < 0).sum()}")
    print(f"  - Missing Channel                : {df['Channel'].isna().sum()}")
    print(f"  - Missing Spend                  : {df['Spend'].isna().sum()}")
    print(f"  - Missing Conversions            : {df['Conversions'].isna().sum()}")
    print(f"  - Missing CPC                    : {df['CPC'].isna().sum()}")
    print(f"  - Missing Conversion_Rate        : {df['Conversion_Rate'].isna().sum()}")
    print(f"  - Missing Cost_Per_Conversion    : {df['Cost_Per_Conversion'].isna().sum()}")
    print(f"  - Active stored as Yes/No        : {df['Active'].dtype}")
    print(f"  - Conversions stored as float    : {df['Conversions'].dtype}")


if __name__ == "__main__":
    main()
