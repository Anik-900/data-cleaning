"""
sessions.py
-----------
In-memory session store for Open Julius.

Each session keeps:
  - ns:        the persistent Python execution namespace (variables survive
               across messages, like a notebook kernel)
  - datasets:  metadata for every uploaded file (variable name, filename, df)
  - contents:  the running Gemini conversation history
  - context:   a text summary of the loaded data, fed to the model each turn

NOTE: this is intentionally simple (a process-local dict). For production you
would persist sessions to Redis/DB and run code in an isolated container.
"""

import threading
import uuid

import pandas as pd

from executor import build_namespace

_LOCK = threading.Lock()
_SESSIONS = {}

# How many sample rows to show the model per dataset.
_SAMPLE_ROWS = 5
_MAX_COLS_IN_CONTEXT = 80


def create_session() -> str:
    session_id = uuid.uuid4().hex
    with _LOCK:
        _SESSIONS[session_id] = {
            "ns": build_namespace(),
            "datasets": [],      # list of {"var", "name", "rows", "cols"}
            "contents": [],      # Gemini conversation history
            "context": "",       # text description of loaded data
        }
    return session_id


def get_session(session_id: str):
    return _SESSIONS.get(session_id)


def _describe_dataframe(var: str, name: str, df: pd.DataFrame) -> str:
    cols = list(df.columns)[:_MAX_COLS_IN_CONTEXT]
    col_lines = []
    for col in cols:
        dtype = str(df[col].dtype)
        col_lines.append(f"  - {col} ({dtype})")
    extra = ""
    if len(df.columns) > _MAX_COLS_IN_CONTEXT:
        extra = f"\n  ... and {len(df.columns) - _MAX_COLS_IN_CONTEXT} more columns"

    try:
        sample = df.head(_SAMPLE_ROWS).to_string(max_cols=20)
    except Exception:
        sample = "(could not render sample)"

    return (
        f"Variable `{var}`  (from file: {name})\n"
        f"Shape: {df.shape[0]} rows x {df.shape[1]} columns\n"
        f"Columns:\n" + "\n".join(col_lines) + extra + "\n"
        f"First {_SAMPLE_ROWS} rows:\n{sample}\n"
    )


def _rebuild_context(session) -> None:
    if not session["datasets"]:
        session["context"] = ""
        return
    blocks = []
    for ds in session["datasets"]:
        df = session["ns"][ds["var"]]
        blocks.append(_describe_dataframe(ds["var"], ds["name"], df))
    session["context"] = "\n".join(blocks)


def add_dataframe(session_id: str, filename: str, df: pd.DataFrame) -> dict:
    """Register a DataFrame in the session and expose it to the namespace.

    The first dataset is `df`, the next `df2`, `df3`, ...
    Returns a small preview dict for the frontend.
    """
    session = _SESSIONS[session_id]
    with _LOCK:
        index = len(session["datasets"]) + 1
        var = "df" if index == 1 else f"df{index}"

        session["ns"][var] = df
        session["datasets"].append({
            "var": var,
            "name": filename,
            "rows": int(df.shape[0]),
            "cols": int(df.shape[1]),
        })
        _rebuild_context(session)

    # Build a JSON-safe preview (first rows + column info) for the UI.
    preview_df = df.head(20)
    columns = [
        {"name": str(c), "dtype": str(df[c].dtype)} for c in df.columns
    ]
    rows = preview_df.astype(object).where(pd.notnull(preview_df), None)
    rows = rows.values.tolist()
    rows = [[_jsonable(v) for v in row] for row in rows]

    return {
        "var": var,
        "name": filename,
        "rows": int(df.shape[0]),
        "cols": int(df.shape[1]),
        "columns": columns,
        "preview": rows,
    }


def _jsonable(value):
    """Coerce numpy / pandas scalars to plain JSON-safe values."""
    if value is None:
        return None
    try:
        import numpy as np
        if isinstance(value, (np.integer,)):
            return int(value)
        if isinstance(value, (np.floating,)):
            f = float(value)
            return f if f == f else None  # drop NaN
        if isinstance(value, (np.bool_,)):
            return bool(value)
    except Exception:
        pass
    if isinstance(value, float) and value != value:  # NaN
        return None
    if isinstance(value, (int, float, bool, str)):
        return value
    return str(value)
