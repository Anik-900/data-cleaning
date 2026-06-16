# Cleaning Summary — Marketing Campaign Dataset

This report shows the measurable impact of running `src/cleaning_pipeline.py`
on the synthetic messy input at `data/raw/marketing_campaign_messy.csv`.

## Headline metrics

| Metric                                | Before     | After    | Change         |
|---------------------------------------|------------|----------|----------------|
| Rows                                  | 2,000      | 2,000    | 0 rows dropped |
| Total missing values                  | 1,551      | 0        | -1,551         |
| Rows with negative Spend              | 15         | 0        | -15            |
| Max Spend (extreme outlier)           | 500,000.00 | 4,316.21 | capped via IQR |
| Rows with Start_Date > End_Date       | 78         | 0        | -78            |
| `Active` column dtype                 | object     | bool     | type-fixed     |
| `Conversions` column dtype            | float64    | int64    | type-fixed     |

## Per-column missing values

| Column                | Missing (before) | Missing (after) |
|-----------------------|-----------------:|----------------:|
| Channel               | 100              | 0               |
| Spend                 | 294              | 0               |
| Conversions           | 200              | 0               |
| CPC                   | 294              | 0               |
| Conversion_Rate       | 200              | 0               |
| Cost_Per_Conversion   | 463              | 0               |

## Cleaning steps applied

1. **Fix negative values** in `Spend`, `CPC`, `Cost_Per_Conversion` using `abs()`.
2. **Cap extreme outliers** above `Q3 + 1.5 * IQR` using the column median
   (applied to `Spend`, `CPC`, `Cost_Per_Conversion`).
3. **Fill missing values** — median for numeric columns, mode for `Channel`.
4. **Convert dates** — `Start_Date` and `End_Date` parsed to `datetime`.
5. **Fix invalid date order** — rows where `Start_Date > End_Date` are swapped.
6. **Recalculate derived metrics** (`CTR`, `CPC`, `Conversion_Rate`,
   `Cost_Per_Conversion`) so they stay consistent with the corrected source columns.
7. **Optimise types** — `Active` to `bool`, `Conversions` to `int`.

## Reproducing this report

```bash
pip install -r requirements.txt
python src/generate_messy_data.py        # writes data/raw/marketing_campaign_messy.csv
python src/cleaning_pipeline.py          # writes data/cleaned/marketing_campaign_clean.csv
```

The pipeline is deterministic: the exact same numbers above are reproduced on
every run.
