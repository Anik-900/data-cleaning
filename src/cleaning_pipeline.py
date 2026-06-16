"""
cleaning_pipeline.py
--------------------
End-to-end, reproducible data cleaning pipeline for the marketing campaign
dataset.

Reads the messy raw file from `data/raw/marketing_campaign_messy.csv`,
applies a deterministic sequence of cleaning steps, writes the cleaned
output to `data/cleaned/marketing_campaign_clean.csv`, and prints a short
before/after summary.

Cleaning steps
--------------
1.  Fix negative values   - Spend, CPC, Cost_Per_Conversion (take absolute value)
2.  Cap extreme outliers  - IQR method, replace values above the upper bound with the column median
3.  Fill missing values   - median for numeric columns, mode for the categorical Channel column
4.  Convert dates         - Start_Date and End_Date converted to datetime
5.  Fix invalid dates     - rows where Start_Date > End_Date are swapped
6.  Recalculate metrics   - CTR, CPC, Conversion_Rate, Cost_Per_Conversion are recomputed from the corrected source columns
7.  Optimise types        - Active becomes bool, Conversions becomes int

Usage
-----
    python src/cleaning_pipeline.py

The script is safe to re-run; it always reproduces the same output for the
same input.
"""

from __future__ import annotations

from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RAW_PATH = ROOT / "data" / "raw" / "marketing_campaign_messy.csv"
CLEAN_PATH = ROOT / "data" / "cleaned" / "marketing_campaign_clean.csv"


# ---------------------------------------------------------------------------
# Cleaning steps
# ---------------------------------------------------------------------------

def fix_negative_values(df: pd.DataFrame, columns: Iterable[str]) -> pd.DataFrame:
    """Replace negative values with their absolute value."""
    for col in columns:
        df[col] = df[col].abs()
    return df


def cap_outliers_iqr(df: pd.DataFrame, columns: Iterable[str]) -> pd.DataFrame:
    """Cap extreme outliers above Q3 + 1.5 * IQR with the column median."""
    for col in columns:
        q1 = df[col].quantile(0.25)
        q3 = df[col].quantile(0.75)
        iqr = q3 - q1
        upper = q3 + 1.5 * iqr
        median = df[col].median()
        df.loc[df[col] > upper, col] = median
    return df


def fill_missing_values(df: pd.DataFrame) -> pd.DataFrame:
    """Fill numeric NaNs with the column median, Channel with its mode."""
    df["Channel"] = df["Channel"].fillna(df["Channel"].mode()[0])
    for col in ["Spend", "Conversions", "CPC", "Conversion_Rate", "Cost_Per_Conversion"]:
        df[col] = df[col].fillna(df[col].median())
    return df


def convert_dates(df: pd.DataFrame) -> pd.DataFrame:
    """Parse the date columns into proper datetime."""
    df["Start_Date"] = pd.to_datetime(df["Start_Date"], errors="coerce")
    df["End_Date"] = pd.to_datetime(df["End_Date"], errors="coerce")
    return df


def fix_invalid_date_order(df: pd.DataFrame) -> pd.DataFrame:
    """Swap Start_Date and End_Date wherever Start > End."""
    mask = df["Start_Date"] > df["End_Date"]
    df.loc[mask, ["Start_Date", "End_Date"]] = df.loc[
        mask, ["End_Date", "Start_Date"]
    ].values
    return df


def recalculate_derived_metrics(df: pd.DataFrame) -> pd.DataFrame:
    """Recompute CTR, CPC, Conversion_Rate, Cost_Per_Conversion from cleaned source columns."""
    df["CTR"] = (df["Clicks"] / df["Impressions"] * 100).round(2)
    df["CPC"] = (df["Spend"] / df["Clicks"]).round(2)
    df["Conversion_Rate"] = (df["Conversions"] / df["Clicks"] * 100).round(2)
    df["Cost_Per_Conversion"] = (df["Spend"] / df["Conversions"]).round(2)
    df["Cost_Per_Conversion"] = df["Cost_Per_Conversion"].replace([np.inf, -np.inf], 0)
    return df


def optimise_types(df: pd.DataFrame) -> pd.DataFrame:
    """Active -> bool, Conversions -> int."""
    df["Active"] = df["Active"].map({"Yes": True, "No": False}).astype(bool)
    df["Conversions"] = df["Conversions"].astype(int)
    return df


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

def quality_snapshot(df: pd.DataFrame, label: str) -> dict:
    """Return a small dict describing key quality indicators."""
    return {
        "label": label,
        "rows": len(df),
        "missing_total": int(df.isnull().sum().sum()),
        "negative_spend": int((df["Spend"] < 0).sum()) if df["Spend"].dtype.kind in "fi" else 0,
        "max_spend": float(df["Spend"].max()) if df["Spend"].dtype.kind in "fi" else float("nan"),
        "invalid_date_order": int((pd.to_datetime(df["Start_Date"], errors="coerce") >
                                   pd.to_datetime(df["End_Date"], errors="coerce")).sum()),
        "active_dtype": str(df["Active"].dtype),
        "conversions_dtype": str(df["Conversions"].dtype),
    }


def print_summary(before: dict, after: dict) -> None:
    """Print a concise before/after report."""
    print()
    print("=" * 72)
    print("Cleaning summary")
    print("=" * 72)
    metrics = [
        ("Rows", "rows"),
        ("Total missing values", "missing_total"),
        ("Rows with negative Spend", "negative_spend"),
        ("Max Spend", "max_spend"),
        ("Rows with Start_Date > End_Date", "invalid_date_order"),
        ("Active dtype", "active_dtype"),
        ("Conversions dtype", "conversions_dtype"),
    ]
    print(f"{'Metric':<35} {'Before':>17} {'After':>17}")
    print("-" * 72)
    for label, key in metrics:
        b = before[key]
        a = after[key]
        if isinstance(b, float):
            b = f"{b:,.2f}"
        if isinstance(a, float):
            a = f"{a:,.2f}"
        print(f"{label:<35} {str(b):>17} {str(a):>17}")
    print("=" * 72)


# ---------------------------------------------------------------------------
# Pipeline orchestration
# ---------------------------------------------------------------------------

def clean(df: pd.DataFrame) -> pd.DataFrame:
    """Apply the full cleaning pipeline to a DataFrame and return the result."""
    df = df.copy()
    df = fix_negative_values(df, ["Spend", "CPC", "Cost_Per_Conversion"])
    df = cap_outliers_iqr(df, ["Spend", "CPC", "Cost_Per_Conversion"])
    df = fill_missing_values(df)
    df = convert_dates(df)
    df = fix_invalid_date_order(df)
    df = recalculate_derived_metrics(df)
    df = optimise_types(df)
    return df


def main() -> None:
    if not RAW_PATH.exists():
        raise FileNotFoundError(
            f"Raw input not found at {RAW_PATH}. "
            "Run `python src/generate_messy_data.py` first."
        )

    raw = pd.read_csv(RAW_PATH)
    before = quality_snapshot(raw, "before")

    cleaned = clean(raw)
    after = quality_snapshot(cleaned, "after")

    CLEAN_PATH.parent.mkdir(parents=True, exist_ok=True)
    cleaned.to_csv(CLEAN_PATH, index=False)

    print(f"Read  : {RAW_PATH}")
    print(f"Wrote : {CLEAN_PATH}")
    print_summary(before, after)


if __name__ == "__main__":
    main()
