"""
Production RAG Streamlit App
============================
Run:
    cd rag_app
    pip install -r requirements.txt
    cp .env.example .env   # add your OPENAI_API_KEY
    streamlit run app.py
"""

import os
import tempfile

import streamlit as st
from dotenv import load_dotenv

from rag import RAGEngine

load_dotenv()

st.set_page_config(
    page_title="RAG Knowledge Base",
    layout="wide",
    page_icon="🧠",
)

# ============================================================
# API KEY CHECK
# ============================================================
if not os.getenv("OPENAI_API_KEY"):
    st.error(
        "⚠️ OPENAI_API_KEY not found. "
        "Copy .env.example to .env and add your key, or set it in "
        "Streamlit Cloud → Settings → Secrets."
    )
    st.stop()

# ============================================================
# SESSION STATE
# ============================================================
if "engine" not in st.session_state:
    st.session_state.engine = RAGEngine(collection_name="user_docs")
if "messages" not in st.session_state:
    st.session_state.messages = []

engine: RAGEngine = st.session_state.engine

# ============================================================
# SIDEBAR — Document Upload + Stats
# ============================================================
with st.sidebar:
    st.title("📚 Knowledge Base")

    uploaded_files = st.file_uploader(
        "Upload PDF / DOCX / TXT",
        type=["pdf", "docx", "txt"],
        accept_multiple_files=True,
    )

    if uploaded_files and st.button("🚀 Ingest Documents", use_container_width=True):
        with st.spinner("Processing..."):
            total_chunks = 0
            for f in uploaded_files:
                suffix = "." + f.name.split(".")[-1]
                with tempfile.NamedTemporaryFile(
                    delete=False, suffix=suffix
                ) as tmp:
                    tmp.write(f.getbuffer())
                    tmp_path = tmp.name
                try:
                    n = engine.ingest(tmp_path)
                    total_chunks += n
                finally:
                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
            st.success(
                f"✅ Ingested {total_chunks} chunks from {len(uploaded_files)} file(s)"
            )

    st.divider()
    url = st.text_input("Or paste a URL:", placeholder="https://example.com/article")
    if url and st.button("🌐 Ingest URL", use_container_width=True):
        with st.spinner("Fetching..."):
            try:
                n = engine.ingest(url)
                st.success(f"✅ Ingested {n} chunks from URL")
            except Exception as e:
                st.error(f"Failed: {e}")

    st.divider()
    st.subheader("📊 Stats")
    stats = engine.stats()
    col1, col2 = st.columns(2)
    col1.metric("Chunks", stats["documents_indexed"])
    col2.metric("Cost", f"${stats['total_cost_usd']:.4f}")

    if st.button("🗑️ Clear chat history", use_container_width=True):
        engine.reset_history()
        st.session_state.messages = []
        st.rerun()

# ============================================================
# MAIN — Chat Interface
# ============================================================
st.title("🧠 Chat With Your Documents")
st.caption(
    "RAG-powered knowledge base • Hybrid search (vector + BM25) • "
    "Citation-grounded answers"
)

# Display history
for msg in st.session_state.messages:
    with st.chat_message(msg["role"]):
        st.markdown(msg["content"])
        if "sources" in msg:
            with st.expander(f"📎 {len(msg['sources'])} sources"):
                for i, s in enumerate(msg["sources"]):
                    st.markdown(
                        f"**[Source {i + 1}]** `{s['source']}` "
                        f"(page {s.get('page', 1)})"
                    )
                    st.caption(s["text"][:300] + "...")

# Chat input
if query := st.chat_input("Ask a question about your documents..."):
    if engine.collection.count() == 0:
        st.warning("⚠️ Please upload documents first.")
        st.stop()

    st.session_state.messages.append({"role": "user", "content": query})
    with st.chat_message("user"):
        st.markdown(query)

    with st.chat_message("assistant"):
        with st.spinner("Thinking..."):
            result = engine.answer(query)

        st.markdown(result["answer"])

        with st.expander(
            f"📎 {len(result['sources'])} sources • "
            f"${result['cost_usd']:.4f} total cost"
        ):
            for i, s in enumerate(result["sources"]):
                st.markdown(
                    f"**[Source {i + 1}]** `{s['source']}` "
                    f"(page {s.get('page', 1)})"
                )
                st.caption(s["text"][:300] + "...")

        st.session_state.messages.append({
            "role": "assistant",
            "content": result["answer"],
            "sources": result["sources"],
        })
