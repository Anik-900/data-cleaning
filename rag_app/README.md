# 🧠 Production RAG Knowledge Base

Chat with your PDFs, DOCX, TXT files, and any web URL using GPT-4 + hybrid search.

## ✨ Features

- **Multi-format ingestion**: PDF, DOCX, TXT, web URLs
- **Hybrid retrieval**: Vector search (ChromaDB) + BM25 keyword search + Reciprocal Rank Fusion
- **LLM reranking**: Higher precision than pure vector search
- **Citation-grounded answers**: Every response cites source + page number
- **Conversation memory**: Multi-turn chat with context awareness
- **Cost tracking**: Real-time USD spend per query

## 🛠️ Tech Stack

- Python 3.10+
- OpenAI API (`text-embedding-3-small`, `gpt-4o-mini`)
- ChromaDB (persistent vector store)
- `rank_bm25` (keyword search)
- Streamlit (UI)

## 🚀 Quick Start

```bash
cd rag_app
pip install -r requirements.txt
cp .env.example .env       # add your OPENAI_API_KEY
streamlit run app.py
```

Open the URL Streamlit prints (usually `http://localhost:8501`).

## ☁️ Deploy to Streamlit Cloud (FREE)

1. Push the repo to GitHub.
2. Go to [share.streamlit.io](https://share.streamlit.io).
3. Sign in with GitHub → **New app** → select this repo.
4. Set main file path to `rag_app/app.py`.
5. In **Advanced settings → Secrets**, paste:
   ```
   OPENAI_API_KEY = "sk-proj-..."
   ```
6. Deploy. You get a public URL to put in your portfolio / proposals.

## 💼 Use Cases

- Legal contract Q&A
- Customer support knowledge base
- Internal company wiki chatbot
- Research paper analysis
- Compliance document review

## 📊 Performance

- Indexing: ~500 pages/min
- Query latency: 2–4 seconds (with reranking)
- Cost: ~$0.003 per query (GPT-4o-mini)

## 🏗️ Architecture

```
User Question
    │
    ├──► Vector Search (ChromaDB)  ──┐
    │                                 ├──► Reciprocal Rank Fusion
    └──► BM25 Keyword Search       ──┘
              │
              └──► LLM Reranking (top 3)
                        │
                        └──► GPT-4o-mini Generation (with citations)
```

## 🧩 Customisation

- **Different LLM provider**: replace `_client()` in `rag.py` with Anthropic, Groq, or
  any OpenAI-compatible API (Together.ai, OpenRouter).
- **Different vector DB**: swap `chromadb` for Pinecone, Weaviate, or Qdrant in `RAGEngine`.
- **Domain-specific prompt**: edit the `system_msg` inside `RAGEngine.answer()`.

## 📜 License

MIT — use freely in client projects.
