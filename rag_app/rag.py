"""
Production RAG Engine
=====================
Supports: PDF, DOCX, TXT, URL ingestion
Features:
  - Hybrid search (vector + BM25 keyword) with Reciprocal Rank Fusion
  - LLM-based reranking for higher precision
  - Citation tracking (source + page)
  - Conversation memory
  - Real-time cost tracking
"""

import os
import hashlib
import tempfile
from pathlib import Path
from typing import List, Dict, Tuple
from dataclasses import dataclass, field

import requests
import numpy as np
import tiktoken
from openai import OpenAI
import chromadb
from chromadb.utils import embedding_functions
from rank_bm25 import BM25Okapi
from pypdf import PdfReader
from docx import Document
from bs4 import BeautifulSoup


# ============================================================
# CONFIG
# ============================================================
EMBED_MODEL = "text-embedding-3-small"   # $0.02 per 1M tokens
LLM_MODEL = "gpt-4o-mini"                # $0.15 input / $0.60 output per 1M tokens
CHUNK_SIZE = 500                          # tokens per chunk
CHUNK_OVERLAP = 50                        # token overlap between chunks
TOP_K_VECTOR = 8                          # initial retrieval count
TOP_K_FINAL = 3                           # final chunks after rerank

PRICING = {
    "text-embedding-3-small": {"input": 0.02 / 1_000_000},
    "gpt-4o-mini": {
        "input":  0.15 / 1_000_000,
        "output": 0.60 / 1_000_000,
    },
}


def _client() -> OpenAI:
    """Lazy OpenAI client (so importing the module doesn't crash without a key)."""
    return OpenAI(api_key=os.getenv("OPENAI_API_KEY"))


_encoder = tiktoken.encoding_for_model("gpt-4o-mini")


# ============================================================
# DATA STRUCTURES
# ============================================================
@dataclass
class Chunk:
    text: str
    source: str
    chunk_id: str
    page: int = 0
    metadata: dict = field(default_factory=dict)


@dataclass
class CostTracker:
    embed_tokens: int = 0
    input_tokens: int = 0
    output_tokens: int = 0

    @property
    def total_cost(self) -> float:
        e = self.embed_tokens * PRICING[EMBED_MODEL]["input"]
        i = self.input_tokens * PRICING[LLM_MODEL]["input"]
        o = self.output_tokens * PRICING[LLM_MODEL]["output"]
        return e + i + o


# ============================================================
# DOCUMENT LOADERS
# ============================================================
def load_pdf(file_path: str) -> List[Tuple[str, int]]:
    """Returns list of (page_text, page_number)."""
    reader = PdfReader(file_path)
    return [(page.extract_text() or "", i + 1) for i, page in enumerate(reader.pages)]


def load_docx(file_path: str) -> List[Tuple[str, int]]:
    doc = Document(file_path)
    text = "\n".join(p.text for p in doc.paragraphs if p.text.strip())
    return [(text, 1)]


def load_txt(file_path: str) -> List[Tuple[str, int]]:
    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        return [(f.read(), 1)]


def load_url(url: str) -> List[Tuple[str, int]]:
    resp = requests.get(
        url,
        timeout=15,
        headers={"User-Agent": "Mozilla/5.0 (RAGBot)"},
    )
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")
    for tag in soup(["script", "style", "nav", "footer", "header"]):
        tag.decompose()
    return [(soup.get_text(separator=" ", strip=True), 1)]


def load_document(source: str) -> List[Tuple[str, int]]:
    """Dispatch loader based on source type."""
    if source.startswith(("http://", "https://")):
        return load_url(source)
    ext = Path(source).suffix.lower()
    if ext == ".pdf":
        return load_pdf(source)
    if ext == ".docx":
        return load_docx(source)
    if ext == ".txt":
        return load_txt(source)
    raise ValueError(f"Unsupported file format: {ext}")


# ============================================================
# CHUNKING (token-based with overlap)
# ============================================================
def chunk_text(text: str, source: str, page: int = 1) -> List[Chunk]:
    if not text or not text.strip():
        return []

    tokens = _encoder.encode(text)
    chunks: List[Chunk] = []
    step = CHUNK_SIZE - CHUNK_OVERLAP

    for i in range(0, len(tokens), step):
        chunk_tokens = tokens[i:i + CHUNK_SIZE]
        if not chunk_tokens:
            continue
        chunk_text_str = _encoder.decode(chunk_tokens)
        chunk_id = hashlib.md5(
            f"{source}_{page}_{i}".encode()
        ).hexdigest()[:12]
        chunks.append(Chunk(
            text=chunk_text_str,
            source=source,
            chunk_id=chunk_id,
            page=page,
            metadata={"start_token": i, "n_tokens": len(chunk_tokens)},
        ))
    return chunks


# ============================================================
# RAG ENGINE
# ============================================================
class RAGEngine:
    """
    Main RAG engine. Persists vector store to ./chroma_db (configurable).
    Usage:
        engine = RAGEngine()
        engine.ingest("mydoc.pdf")
        result = engine.answer("What is X?")
    """

    def __init__(
        self,
        collection_name: str = "default",
        persist_path: str = "./chroma_db",
    ):
        self.chroma = chromadb.PersistentClient(path=persist_path)
        self.embed_fn = embedding_functions.OpenAIEmbeddingFunction(
            api_key=os.getenv("OPENAI_API_KEY"),
            model_name=EMBED_MODEL,
        )
        self.collection = self.chroma.get_or_create_collection(
            name=collection_name,
            embedding_function=self.embed_fn,
        )
        self.cost = CostTracker()
        self.bm25: BM25Okapi | None = None
        self.bm25_chunks: List[Chunk] = []
        self.chat_history: List[Dict] = []

    # ------------------------------------------------------------
    # INGESTION
    # ------------------------------------------------------------
    def ingest(self, source: str) -> int:
        """Ingest a file path or URL. Returns the number of chunks added."""
        pages = load_document(source)
        all_chunks: List[Chunk] = []
        for text, page_num in pages:
            all_chunks.extend(chunk_text(text, source, page_num))

        if not all_chunks:
            return 0

        # Track embedding cost
        total_tokens = sum(len(_encoder.encode(c.text)) for c in all_chunks)
        self.cost.embed_tokens += total_tokens

        # Add to ChromaDB (auto-embeds via embedding function)
        self.collection.add(
            documents=[c.text for c in all_chunks],
            ids=[c.chunk_id for c in all_chunks],
            metadatas=[{
                "source": c.source,
                "page": c.page,
                **c.metadata,
            } for c in all_chunks],
        )

        # Update BM25 index in-memory
        self.bm25_chunks.extend(all_chunks)
        tokenized = [c.text.lower().split() for c in self.bm25_chunks]
        self.bm25 = BM25Okapi(tokenized)

        return len(all_chunks)

    # ------------------------------------------------------------
    # HYBRID RETRIEVAL (vector + BM25 + RRF)
    # ------------------------------------------------------------
    def retrieve(self, query: str) -> List[Dict]:
        # 1) Vector search
        vector_hits: List[Dict] = []
        if self.collection.count() > 0:
            vec_res = self.collection.query(
                query_texts=[query],
                n_results=min(TOP_K_VECTOR, self.collection.count()),
            )
            if vec_res["documents"]:
                for doc, meta, dist in zip(
                    vec_res["documents"][0],
                    vec_res["metadatas"][0],
                    vec_res["distances"][0],
                ):
                    vector_hits.append({
                        "text": doc,
                        "source": meta.get("source", "unknown"),
                        "page": meta.get("page", 1),
                        "vector_score": 1 - dist,
                    })

        # 2) BM25 keyword search
        bm25_hits: List[Dict] = []
        if self.bm25 and self.bm25_chunks:
            scores = self.bm25.get_scores(query.lower().split())
            top_indices = np.argsort(scores)[-TOP_K_VECTOR:][::-1]
            for idx in top_indices:
                if scores[idx] > 0:
                    c = self.bm25_chunks[idx]
                    bm25_hits.append({
                        "text": c.text,
                        "source": c.source,
                        "page": c.page,
                        "bm25_score": float(scores[idx]),
                    })

        # 3) Reciprocal Rank Fusion
        merged: Dict[str, Dict] = {}
        for rank, hit in enumerate(vector_hits):
            key = hit["text"][:120]
            merged[key] = {**hit, "rrf": 1 / (rank + 60)}

        for rank, hit in enumerate(bm25_hits):
            key = hit["text"][:120]
            if key in merged:
                merged[key]["rrf"] += 1 / (rank + 60)
            else:
                merged[key] = {**hit, "rrf": 1 / (rank + 60)}

        ranked = sorted(merged.values(), key=lambda x: x["rrf"], reverse=True)
        return ranked[:TOP_K_FINAL]

    # ------------------------------------------------------------
    # OPTIONAL: LLM RERANKING (slower, more accurate)
    # ------------------------------------------------------------
    def llm_rerank(self, query: str, hits: List[Dict]) -> List[Dict]:
        if len(hits) <= 1:
            return hits

        prompt = (
            "Rate each passage 0-10 for relevance to the question.\n"
            'Return ONLY a comma-separated list of scores in order, '
            'e.g. "8,3,7"\n\n'
            f"Question: {query}\n\nPassages:\n"
        )
        for i, h in enumerate(hits):
            prompt += f"\n[{i + 1}] {h['text'][:300]}\n"

        try:
            resp = _client().chat.completions.create(
                model=LLM_MODEL,
                messages=[{"role": "user", "content": prompt}],
                temperature=0,
            )
            self.cost.input_tokens += resp.usage.prompt_tokens
            self.cost.output_tokens += resp.usage.completion_tokens

            scores = [
                float(s.strip())
                for s in resp.choices[0].message.content.split(",")
            ]
            for h, s in zip(hits, scores):
                h["rerank_score"] = s
            return sorted(
                hits, key=lambda x: x.get("rerank_score", 0), reverse=True
            )
        except Exception:
            # If reranking fails, fall back to RRF order
            return hits

    # ------------------------------------------------------------
    # ANSWER GENERATION (with citations)
    # ------------------------------------------------------------
    def answer(self, query: str, use_history: bool = True) -> Dict:
        hits = self.retrieve(query)
        if not hits:
            return {
                "answer": "I don't have any documents indexed yet. "
                          "Please upload some first.",
                "sources": [],
                "cost_usd": self.cost.total_cost,
                "tokens": {"input": 0, "output": 0},
            }

        hits = self.llm_rerank(query, hits)

        # Build context with citation markers
        context_blocks = []
        for i, h in enumerate(hits):
            context_blocks.append(
                f"[Source {i + 1}: {h['source']}, page {h.get('page', 1)}]\n"
                f"{h['text']}"
            )
        context = "\n\n---\n\n".join(context_blocks)

        system_msg = (
            "You are a precise research assistant. Follow these rules strictly:\n"
            "1. Answer ONLY using the provided sources.\n"
            "2. Cite sources inline as [Source 1], [Source 2], etc.\n"
            "3. If the sources don't contain the answer, say "
            "\"I don't have enough information in the provided documents.\"\n"
            "4. Be concise — 2-4 sentences unless detail is requested.\n"
            "5. Never make up facts."
        )

        messages = [{"role": "system", "content": system_msg}]
        if use_history:
            messages.extend(self.chat_history[-4:])  # last 2 turns
        messages.append({
            "role": "user",
            "content": f"CONTEXT:\n{context}\n\nQUESTION: {query}",
        })

        resp = _client().chat.completions.create(
            model=LLM_MODEL,
            messages=messages,
            temperature=0.2,
        )
        answer = resp.choices[0].message.content
        self.cost.input_tokens += resp.usage.prompt_tokens
        self.cost.output_tokens += resp.usage.completion_tokens

        # Update chat history
        self.chat_history.append({"role": "user", "content": query})
        self.chat_history.append({"role": "assistant", "content": answer})

        return {
            "answer": answer,
            "sources": hits,
            "cost_usd": self.cost.total_cost,
            "tokens": {
                "input": resp.usage.prompt_tokens,
                "output": resp.usage.completion_tokens,
            },
        }

    # ------------------------------------------------------------
    # UTILITIES
    # ------------------------------------------------------------
    def reset_history(self) -> None:
        self.chat_history = []

    def stats(self) -> Dict:
        return {
            "documents_indexed": self.collection.count(),
            "total_cost_usd": round(self.cost.total_cost, 4),
            "embed_tokens": self.cost.embed_tokens,
            "llm_input_tokens": self.cost.input_tokens,
            "llm_output_tokens": self.cost.output_tokens,
        }
