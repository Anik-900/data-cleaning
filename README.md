# Marketing Campaign Data Cleaning

Data cleaning and exploratory analysis of a messy marketing campaign dataset using Python and pandas.

## Project Overview

This project demonstrates a complete data cleaning pipeline on a marketing campaign dataset that contains common real-world issues:

- Negative values in `Spend`, `CPC`, and `Cost_Per_Conversion` columns
- Missing values (`NaN`) across multiple columns
- Inconsistent data types
- Duplicate or invalid entries

## Dataset

The dataset (`market campaign data messy.ipynb`) contains marketing campaign performance metrics:

| Column | Description |
|---|---|
| `Campaign_ID` | Unique campaign identifier |
| `Campaign_Name` | Campaign name with quarter and theme |
| `Start_Date` / `End_Date` | Campaign duration |
| `Channel` | Marketing channel (TikTok, Facebook, Email, Google Ads) |
| `Impressions` | Total ad impressions |
| `Clicks` | Total clicks received |
| `Spend` | Campaign spend (USD) |
| `Conversions` | Number of conversions |
| `Active` | Campaign active status (Yes/No) |
| `CTR` | Click-through rate (%) |
| `CPC` | Cost per click |
| `Conversion_Rate` | Conversion rate (%) |
| `Cost_Per_Conversion` | Cost per conversion |

## Setup

### Prerequisites

- Python 3.10 or higher
- Git

### Installation

```bash
# Clone the repository
git clone https://github.com/Anik-900/data-cleaning.git
cd data-cleaning

# Create a virtual environment
python -m venv venv

# Activate the virtual environment
# On Windows:
venv\Scripts\activate
# On macOS/Linux:
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

### Running the Notebook

**Option 1: VS Code / Kiro / Cursor**
1. Open the project folder in your IDE
2. Open `market campaign data messy.ipynb`
3. Select the venv kernel
4. Run cells with `Shift+Enter`

**Option 2: Jupyter Lab**
```bash
jupyter lab
```

**Option 3: Classic Jupyter**
```bash
jupyter notebook
```

## Project Structure

```
data-cleaning/
├── .gitignore
├── README.md
├── requirements.txt
├── market campaign data messy.ipynb    # Main analysis notebook
└── .kiro/
    └── steering/                        # AI assistant guidelines
```

## Cleaning Workflow

1. **Load & Inspect** — Read CSV, check shape, dtypes, missing values
2. **Detect Anomalies** — Find negative values, outliers, duplicates
3. **Handle Missing Data** — Impute or drop based on column importance
4. **Fix Invalid Values** — Address negative `Spend`, `CPC`, etc.
5. **Type Conversion** — Ensure dates and numerics are correctly typed
6. **Validation** — Cross-check derived metrics (e.g., `CTR = Clicks/Impressions * 100`)
7. **Export** — Save cleaned dataset

## License

MIT
