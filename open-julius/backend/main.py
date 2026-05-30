"""
main.py
-------
FastAPI server for Open Julius.

Endpoints
  GET  /api/health            -> service + config status
  POST /api/session           -> create a new analysis session
  POST /api/upload            -> upload a CSV / Excel file into a session
  POST /api/chat              -> ask a question; runs the Gemini agent loop

It also serves the static frontend (../frontend) at "/".
Run from this directory:   uvicorn main:app --reload
"""

import io
import os
import traceback

from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import pandas as pd
from google.genai import types

import agent
import sessions

# Load backend/.env so GEMINI_API_KEY etc. are available.
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

app = FastAPI(title="Open Julius", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Build the Gemini client lazily so the server still boots without a key
# (the UI can then show a helpful message).
_client = None
_client_error = None
try:
    _client = agent.build_client()
except Exception as exc:  # missing key, etc.
    _client_error = str(exc)


MAX_FILE_MB = 50


# --------------------------------------------------------------------------
# Models
# --------------------------------------------------------------------------
class ChatRequest(BaseModel):
    session_id: str
    message: str


# --------------------------------------------------------------------------
# API routes (registered BEFORE the static mount so they take precedence)
# --------------------------------------------------------------------------
@app.get("/api/health")
def health():
    return {
        "status": "ok",
        "model": agent.MODEL,
        "api_key_configured": _client is not None,
        "detail": _client_error,
    }


@app.post("/api/session")
def new_session():
    session_id = sessions.create_session()
    return {"session_id": session_id, "model": agent.MODEL}


@app.post("/api/upload")
async def upload(session_id: str = Form(...), file: UploadFile = File(...)):
    session = sessions.get_session(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found. Reload the page.")

    raw = await file.read()
    if len(raw) > MAX_FILE_MB * 1024 * 1024:
        raise HTTPException(
            status_code=413,
            detail=f"File too large (limit {MAX_FILE_MB} MB).",
        )

    name = file.filename or "data"
    lower = name.lower()
    try:
        if lower.endswith((".xlsx", ".xls")):
            df = pd.read_excel(io.BytesIO(raw))
        elif lower.endswith(".tsv"):
            df = pd.read_csv(io.BytesIO(raw), sep="\t")
        elif lower.endswith((".json",)):
            df = pd.read_json(io.BytesIO(raw))
        else:
            # default: CSV (try utf-8, fall back to latin-1)
            try:
                df = pd.read_csv(io.BytesIO(raw))
            except UnicodeDecodeError:
                df = pd.read_csv(io.BytesIO(raw), encoding="latin-1")
    except Exception as exc:
        raise HTTPException(
            status_code=400,
            detail=f"Could not read '{name}': {exc}",
        )

    if df.empty:
        raise HTTPException(status_code=400, detail="The file has no rows.")

    preview = sessions.add_dataframe(session_id, name, df)
    return preview


@app.post("/api/chat")
def chat(req: ChatRequest):
    if _client is None:
        raise HTTPException(
            status_code=503,
            detail=(_client_error or "Gemini API key not configured."),
        )

    session = sessions.get_session(req.session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found. Reload the page.")

    message = (req.message or "").strip()
    if not message:
        raise HTTPException(status_code=400, detail="Empty message.")

    # Append the user's message to the persistent conversation history.
    session["contents"].append(
        types.Content(role="user", parts=[types.Part(text=message)])
    )

    try:
        result = agent.run_agent(
            client=_client,
            contents=session["contents"],
            namespace=session["ns"],
            dataset_context=session["context"],
        )
    except Exception as exc:
        traceback.print_exc()
        text = str(exc)
        # Friendly message for the free-tier rate limit (HTTP 429).
        if "429" in text or "RESOURCE_EXHAUSTED" in text:
            raise HTTPException(
                status_code=429,
                detail=(
                    "Gemini free-tier rate limit reached (only a few requests "
                    "per minute are allowed). Please wait ~30 seconds and try "
                    "again. Tip: you can also switch GEMINI_MODEL in your .env "
                    "or enable billing for higher limits."
                ),
            )
        raise HTTPException(status_code=500, detail=f"Agent error: {exc}")

    return result


# --------------------------------------------------------------------------
# Static frontend
# --------------------------------------------------------------------------
_FRONTEND_DIR = os.path.join(os.path.dirname(__file__), "..", "frontend")
_FRONTEND_DIR = os.path.abspath(_FRONTEND_DIR)

if os.path.isdir(_FRONTEND_DIR):
    @app.get("/")
    def index():
        return FileResponse(os.path.join(_FRONTEND_DIR, "index.html"))

    app.mount("/", StaticFiles(directory=_FRONTEND_DIR, html=True), name="frontend")
