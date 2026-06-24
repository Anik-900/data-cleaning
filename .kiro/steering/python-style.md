---
inclusion: always
---

# Python & Data Analysis Style Guide

## General Python Conventions

- Follow PEP 8 for code formatting
- Use 4 spaces for indentation, no tabs
- Maximum line length: 100 characters
- Use type hints for function signatures when reasonable
- Prefer f-strings over `.format()` or `%` formatting

## Naming

- Variables and functions: `snake_case`
- Constants: `UPPER_SNAKE_CASE`
- Classes: `PascalCase`
- DataFrames: descriptive names like `df_campaigns`, not just `df` for production code
- Avoid single-letter variables except for short loops (`i`, `j`) or math (`x`, `y`)

## Pandas Best Practices

- **Avoid `inplace=True`** — return new DataFrames for clarity and chainability
- Prefer method chaining for readability:
  ```python
  result = (
      df
      .dropna(subset=['Spend'])
      .query('Spend > 0')
      .assign(profit=lambda d: d['Revenue'] - d['Spend'])
  )
  ```
- Use `.loc[]` and `.iloc[]` for explicit indexing — avoid chained assignment
- Use `.copy()` when slicing to avoid `SettingWithCopyWarning`
- Prefer vectorized operations over `.apply()` or loops
- Use `pd.NA` over `np.nan` for nullable types when possible

## Data Cleaning Conventions

- Always inspect data first: `.info()`, `.describe()`, `.isna().sum()`, `.duplicated().sum()`
- Document every cleaning decision with a markdown cell explaining the "why"
- Keep raw data immutable — never overwrite original CSV
- Save intermediate cleaned versions: `data_cleaned.csv`, `data_validated.csv`
- For invalid values (e.g., negative `Spend`), prefer one of:
  1. Investigate root cause (data entry error vs. legitimate refund)
  2. Flag with a boolean column (`is_valid`)
  3. Drop only after explicit justification
- Never silently drop rows — always log count of dropped rows

## Notebook Structure

Every notebook should follow this structure:

1. **Header markdown cell** — Title, purpose, author, date
2. **Imports cell** — All imports grouped (stdlib, third-party, local)
3. **Configuration cell** — Constants, file paths, display options
4. **Data loading cell** — Read raw data with clear path
5. **Inspection cells** — Shape, dtypes, missing values
6. **Cleaning cells** — One concern per cell, with markdown explanation
7. **Validation cells** — Verify cleaning worked correctly
8. **Export cell** — Save cleaned data with timestamp/version

## Visualization

- Always set figure size: `plt.figure(figsize=(10, 6))`
- Add titles, axis labels, and legends to every plot
- Use `seaborn` for statistical plots, `matplotlib` for fine control
- Prefer `plotly` for interactive exploration
- Save plots with descriptive filenames if exporting

## Comments & Documentation

- Write **why**, not **what** — code shows what; comments should explain reasoning
- Use markdown cells in notebooks liberally to narrate analysis
- Add docstrings to all custom functions (numpy or Google style)

## File Paths

- **Never hardcode absolute paths** like `C:\Users\...` — use relative paths or `pathlib.Path`
- Use `pathlib.Path` over `os.path` for new code:
  ```python
  from pathlib import Path
  DATA_DIR = Path("data")
  df = pd.read_csv(DATA_DIR / "raw.csv")
  ```

## Reproducibility

- Set random seeds: `np.random.seed(42)`
- Pin dependency versions in `requirements.txt`
- Document Python version used
- Keep notebook execution order linear (run all from top should work)
