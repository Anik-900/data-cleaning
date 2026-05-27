# Marketing Campaign Data Cleaning

A reproducible, end-to-end Python data cleaning project on a 2,000-row marketing
campaign dataset that contains realistic data quality problems: negative values,
extreme outliers, missing entries, swapped dates, inconsistent types, and stale
derived columns.

The project ships with both an **executable pipeline** (`src/cleaning_pipeline.py`)
and a **step-by-step walkthrough notebook** (`notebooks/marketing_campaign_cleaning.ipynb`),
so reviewers can either run the whole thing in one command or read through every
decision.

![Python](https://img.shields.io/badge/Python-3.10%2B-blue?logo=python&logoColor=white)
![Pandas](https://img.shields.io/badge/Pandas-2.x-150458?logo=pandas&logoColor=white)
![NumPy](https://img.shields.io/badge/NumPy-1.24%2B-013243?logo=numpy&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

---

## 📊 Headline Result

The pipeline takes a messy 2,000-row CSV and returns a clean, analysis-ready
file in under a second. Numbers below are reproduced on every run.

| Metric                            | Before     | After    |
|-----------------------------------|-----------:|---------:|
| Total missing values              | 1,551      | **0**    |
| Rows with negative Spend          | 15         | **0**    |
| Max Spend (extreme outlier)       | 500,000.00 | 4,316.21 |
| Rows with Start_Date > End_Date   | 78         | **0**    |
| `Active` column dtype             | object     | **bool** |
| `Conversions` column dtype        | float64    | **int**  |

A more detailed breakdown lives in [`reports/cleaning_summary.md`](reports/cleaning_summary.md).

---

## 🗂️ Project Structure

```
data-cleaning/
├── data/
│   ├── raw/
│   │   └── marketing_campaign_messy.csv       # Synthetic, deterministic input
│   └── cleaned/
│       └── marketing_campaign_clean.csv       # Pipeline output
├── notebooks/
│   └── marketing_campaign_cleaning.ipynb      # Step-by-step walkthrough
├── src/
│   ├── generate_messy_data.py                 # Builds the messy input
│   └── cleaning_pipeline.py                   # Production-style cleaner
├── reports/
│   └── cleaning_summary.md                    # Before/after metrics
├── requirements.txt
├── LICENSE
└── README.md
```

---

## 🚀 Quick Start

```bash
# 1. Clone and install
git clone https://github.com/Anik-900/data-cleaning.git
cd data-cleaning
pip install -r requirements.txt

# 2. Generate the messy input (deterministic, seed = 42)
python src/generate_messy_data.py

# 3. Run the cleaning pipeline
python src/cleaning_pipeline.py
```

The cleaned output will be at `data/cleaned/marketing_campaign_clean.csv` and a
before/after summary is printed to the terminal.

To explore the same logic step-by-step, open the notebook:

```bash
jupyter notebook notebooks/marketing_campaign_cleaning.ipynb
```

---

## 🧹 Cleaning Steps

The pipeline applies seven deterministic steps in order. Every step is a small,
named function in [`src/cleaning_pipeline.py`](src/cleaning_pipeline.py) so each
step can be unit-tested or reused independently.

| #  | Step                              | What it does                                                                     | Columns affected                              |
|----|-----------------------------------|----------------------------------------------------------------------------------|-----------------------------------------------|
| 1  | Fix negative values               | Take absolute value where the metric must be non-negative                        | `Spend`, `CPC`, `Cost_Per_Conversion`         |
| 2  | Cap extreme outliers (IQR)        | Replace values above `Q3 + 1.5 * IQR` with the column median                     | `Spend`, `CPC`, `Cost_Per_Conversion`         |
| 3  | Fill missing values               | Median for numeric columns, mode for the categorical channel column              | `Channel`, `Spend`, `Conversions`, `CPC`, `Conversion_Rate`, `Cost_Per_Conversion` |
| 4  | Convert dates                     | Parse to proper `datetime`                                                       | `Start_Date`, `End_Date`                      |
| 5  | Fix invalid date order            | Swap rows where `Start_Date > End_Date`                                          | `Start_Date`, `End_Date`                      |
| 6  | Recalculate derived metrics       | Recompute `CTR`, `CPC`, `Conversion_Rate`, `Cost_Per_Conversion` from clean inputs | 4 derived columns                              |
| 7  | Optimise types                    | `Active` → `bool`, `Conversions` → `int`                                         | `Active`, `Conversions`                       |

---

## 📋 Dataset Schema

| Column                | Type      | Description                                            |
|-----------------------|-----------|--------------------------------------------------------|
| Campaign_ID           | string    | Unique campaign identifier (`CMP-00001`, `CMP-00002`,…)|
| Campaign_Name         | string    | Human-readable campaign label                          |
| Start_Date            | datetime  | Campaign start date                                    |
| End_Date              | datetime  | Campaign end date                                      |
| Channel               | string    | Marketing channel (Facebook, Google Ads, TikTok, …)    |
| Impressions           | int       | Number of times the ad was shown                       |
| Clicks                | int       | Number of clicks received                              |
| Spend                 | float     | Total spend in USD                                     |
| Conversions           | int       | Number of conversions                                  |
| Active                | bool      | Whether the campaign is currently running              |
| CTR                   | float     | Click-Through Rate, `Clicks / Impressions * 100`       |
| CPC                   | float     | Cost Per Click, `Spend / Clicks`                       |
| Conversion_Rate       | float     | `Conversions / Clicks * 100`                           |
| Cost_Per_Conversion   | float     | `Spend / Conversions`                                  |

---

## 🛠️ Tech Stack

- **Python 3.10+**
- **pandas** for tabular cleaning
- **NumPy** for numeric handling
- **Jupyter** for the walkthrough notebook

---

## 👤 About

Built by **Anik** — Data Analyst with a Bachelor of Pharmacy from Khulna University.
I focus on data cleaning, business intelligence dashboards, and PDF/document
automation. Open to freelance projects.

- GitHub: [@Anik-900](https://github.com/Anik-900)

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file
for details.
