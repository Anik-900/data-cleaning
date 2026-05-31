# Data Analysis Question Bank — from scratch, the professional way

A complete, ordered set of questions/prompts to run a full analysis on any
dataset, with your Julius-style AI (Gemini, Claude, or Copilot). It goes beyond
basic EDA to include what a professional analyst *always* does: frame the
problem first, validate the data, dig for drivers, then communicate and act.

> How to use: replace the placeholders — `[TARGET]` (what you care about, e.g.
> Response/Revenue/Churn), `[METRIC]`, `[CATEGORY]`, `[DATE]`, `[GROUP]` — with
> your real column names. Ask top to bottom, or jump to the stage you need.

---

## Stage 0 — Frame the problem (BEFORE looking at the data)
A pro never analyzes blindly. Decide what "success" means first.

- "What business questions can this dataset realistically answer — and what can it NOT answer?"
- "What is the unit of analysis here (one row = one customer? one transaction? one day)?"
- "If I'm trying to understand/improve [TARGET], which columns are likely drivers, and which are just IDs or noise?"
- "What decisions would change depending on what we find?"

## Stage 1 — First look (understand the data)
- "Profile this dataset: rows, columns, column names, data types, and what it appears to be about."
- "Show me the first 10 rows and the last 5 rows."
- "Give a plain-English description of what each column means and its likely role (identifier, category, numeric measure, date, target)."
- "How was this data likely collected, and over what time period does it span?"

## Stage 2 — Data quality audit (validate before you trust)
- "How many missing values are in each column (counts and %)? Is the missingness random or concentrated?"
- "How many duplicate rows are there? Are there duplicate IDs that should be unique?"
- "Are date and numeric columns stored in the correct type, or as text? Fix and report."
- "Check for impossible or inconsistent values: negatives where impossible, out-of-range dates, future dates, inconsistent category spellings/casing, leading/trailing spaces."
- "Detect outliers in each numeric column (IQR or z-score) and show them on box plots. Are they errors or real extremes?"
- "Is the data balanced (e.g. class balance of [TARGET]), or skewed? Note any sampling bias."
- "Clean the data: handle missing values, duplicates, and types. Explain every choice and show before/after counts."

## Stage 3 — Univariate analysis (one variable at a time)
- "Descriptive statistics (count, mean, median, std, min, max, quartiles) for all numeric columns."
- "Plot the distribution of each key numeric column (histogram + KDE). Note skew and modality."
- "For each categorical column, show value counts and the share of the top categories. Flag high-cardinality columns."
- "Which columns have near-zero variance or are almost entirely one value (low information)?"

## Stage 4 — Bivariate & multivariate (relationships)
- "Correlation heatmap of all numeric columns. Which pairs are most strongly correlated? Watch for multicollinearity."
- "What are the strongest drivers related to [TARGET]? Rank them."
- "Compare [METRIC] across [CATEGORY] (e.g. average [METRIC] by [GROUP]). Show a sorted bar chart."
- "Is the difference in [METRIC] between groups statistically significant? Use the right test and report effect size, not just a p-value."
- "Cross-tabulate [CATEGORY A] vs [CATEGORY B]. Is there an association (chi-square)?"
- "Are there interaction effects (e.g. the effect of [X] on [TARGET] differs by [GROUP])?"

## Stage 5 — Time trends (only if there's a date)
- "Is [METRIC] trending up or down over time? Line chart + quantify the % change."
- "Are there seasonal patterns, cycles, day-of-week, or month effects?"
- "Are there sudden spikes, drops, or anomalies? When, and what might explain them?"
- "Show a rolling average to smooth noise and reveal the underlying trend."

## Stage 6 — Segmentation & deeper patterns
- "Segment the data into meaningful groups (clustering). Describe what makes each segment distinct."
- "Which segment is most valuable / most at risk for [TARGET]?"
- "Are there subgroups where the usual pattern reverses (Simpson's paradox check)?"

## Stage 7 — Modeling & drivers (if prediction is the goal)
- "Build a simple, explainable baseline model to predict [TARGET]. Use a train/test split with a fixed random_state and report honest accuracy/error metrics."
- "Which features matter most (feature importance / coefficients)? Explain in plain English."
- "How well does the model generalize? Show the gap between train and test performance and flag overfitting."
- "What's the cost of being wrong, and is this model good enough to act on?"

## Stage 8 — Sanity checks & rigor (what separates pros from amateurs)
- "Re-derive the 2–3 headline numbers a different way to confirm they're correct."
- "Where could these conclusions be misleading — confounders, correlation vs causation, survivorship/selection bias?"
- "How sensitive are the findings to the cleaning choices we made (e.g. if we kept the outliers)?"
- "What's the sample size behind each rate or average — is any of it too small to trust?"

## Stage 9 — Communicate & act (the deliverable)
- "Write an executive summary: the situation, the key finding, and the recommendation — in that order, in plain language."
- "List the top 5 insights, each with the supporting number and a 'so what' for the business."
- "Recommend 3 concrete next actions, ranked by impact and effort."
- "What additional data or analysis would make these conclusions stronger?"
- "Turn this into a short, shareable report with the most important charts."

---

## ⚡ The one-line shortcuts
When you don't want to go step by step:

- Full auto: "Do a complete, professional exploratory data analysis from scratch — profile, audit quality, clean, univariate, relationships, time trends if any — and show key findings with charts."
- Decision-focused: "Act as a senior data analyst. My goal is to understand/improve [TARGET]. Take this dataset from raw to an executive summary with recommendations, showing your work and charts."
- Quality-only: "Do a thorough data-quality audit and give me a cleaning plan with before/after counts."

## 🧭 The mindset behind the order
1. Frame the problem → 2. Understand the data → 3. Trust it (quality) →
4. Explore (univariate → relationships → time) → 5. Go deeper (segments/models)
→ 6. Pressure-test (sanity & bias) → 7. Communicate & recommend.

Amateurs jump straight to charts. Professionals frame the question first and
pressure-test the answer last.
