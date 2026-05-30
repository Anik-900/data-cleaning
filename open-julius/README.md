# Open Julius — Free AI Data Analyst (Julius AI clone)

Chat with your data in plain English. Upload a CSV/Excel file and ask questions —
**Open Julius** uses **Google Gemini** (free Google AI Studio key) to write and run
Python on your data, then shows you the **code, the output, the charts, and a
plain-language explanation**.

It is a free, self-hosted alternative to [Julius AI](https://julius.ai).

```
┌──────────┐   question    ┌─────────┐  writes code  ┌──────────────┐
│ Frontend │ ────────────▶ │ Gemini  │ ────────────▶ │ Python sandbox│
│  (chat)  │ ◀──────────── │  agent  │ ◀──────────── │ pandas/mpl... │
└──────────┘  code+charts  └─────────┘   results     └──────────────┘
                              ▲  └── sees output, fixes errors, iterates ──┘
```

## How it works (the Julius pattern)

1. You upload data → it's loaded into a pandas DataFrame (`df`).
2. You ask a question → Gemini plans and **writes Python code**.
3. The backend **executes** that code in a sandbox and captures stdout + charts.
4. Gemini **reads the results**, fixes any errors, and iterates (agentic loop).
5. You get the **charts, the code, and a clear written insight**.

## Requirements

- Python 3.10+
- A **free** Google AI Studio API key → https://aistudio.google.com/apikey

## Setup & run

```bash
cd open-julius/backend

# 1. install dependencies (a virtualenv is recommended)
python -m venv .venv && source .venv/bin/activate     # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# 2. add your API key
cp .env.example .env
#   then edit .env and paste your key into GEMINI_API_KEY=...

# 3. start the server
uvicorn main:app --reload --port 8000
```

Now open **http://localhost:8000** in your browser, drop in a CSV, and start asking.

> Quick start: from the project root you can also just run `./run.sh`.

## Project layout

```
open-julius/
├── backend/
│   ├── main.py          # FastAPI server + API routes + serves frontend
│   ├── agent.py         # Gemini agent: function-calling loop (the "brain")
│   ├── executor.py      # Python code interpreter (captures output + charts)
│   ├── sessions.py      # in-memory sessions (namespace, datasets, history)
│   ├── requirements.txt
│   └── .env.example
└── frontend/
    ├── index.html       # chat UI
    ├── style.css        # dark theme
    └── app.js           # upload + chat logic (vanilla JS, no build step)
```

## Configuration (.env)

| Variable          | Default            | Notes                                            |
|-------------------|--------------------|--------------------------------------------------|
| `GEMINI_API_KEY`  | —                  | required; your Google AI Studio key              |
| `GEMINI_MODEL`    | `gemini-2.5-flash` | try `gemini-2.5-pro` for harder analysis         |
| `MAX_AGENT_TURNS` | `12`               | max code/reasoning steps per question            |

## Notes & limitations

- Generated code runs **in the same process** as the server. That's fine for
  local/personal use, but for a public deployment run it inside an isolated
  container (Docker, gVisor, E2B, etc.).
- Sessions are stored in memory — restarting the server clears uploaded data.

## Hitting the free-tier rate limit? (HTTP 429)

Google's **free** Gemini tier allows only a few requests per minute (e.g. 5/min
for `gemini-2.5-flash`). If you analyze quickly you may see a `429
RESOURCE_EXHAUSTED` error. Open Julius now **auto-retries** and waits the time
Gemini suggests, but if you still hit it:

- Wait ~30-60 seconds and ask again.
- Raise `MAX_RETRIES` in `.env`.
- Switch `GEMINI_MODEL` in `.env` (e.g. `gemini-2.0-flash` sometimes has
  separate quota).
- For heavy use, enable billing in Google AI Studio for much higher limits.
```
