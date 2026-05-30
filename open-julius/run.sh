#!/usr/bin/env bash
# Open Julius - one-command setup & launch
set -e

cd "$(dirname "$0")/backend"

# 1. virtualenv
if [ ! -d ".venv" ]; then
  echo "==> Creating virtual environment..."
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate

# 2. dependencies
echo "==> Installing dependencies..."
pip install -q --upgrade pip
pip install -q -r requirements.txt

# 3. .env
if [ ! -f ".env" ]; then
  cp .env.example .env
  echo ""
  echo "  >>> A backend/.env file was created."
  echo "  >>> Edit it and add your Google AI Studio key (GEMINI_API_KEY) before chatting."
  echo "  >>> Get a free key at: https://aistudio.google.com/apikey"
  echo ""
fi

# 4. launch
echo "==> Starting Open Julius at http://localhost:8000"
exec uvicorn main:app --reload --port 8000
