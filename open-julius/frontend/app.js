/* Open Julius - frontend logic (no build step, vanilla JS) */

const API = ""; // same origin (served by FastAPI). Set to "http://localhost:8000" if hosting separately.

let sessionId = null;
let hasData = false;
let busy = false;

const $ = (sel) => document.querySelector(sel);

const els = {
  messages: $("#messages"),
  welcome: $("#welcome"),
  prompt: $("#prompt"),
  send: $("#send"),
  uploadArea: $("#upload-area"),
  fileInput: $("#file-input"),
  datasetList: $("#dataset-list"),
  newChat: $("#new-chat"),
  modelBadge: $("#model-badge"),
  keyBadge: $("#key-badge"),
  previewModal: $("#preview-modal"),
  previewBody: $("#preview-body"),
  previewTitle: $("#preview-title"),
  previewClose: $("#preview-close"),
};

/* ---------------- helpers ---------------- */
function toast(msg, isError) {
  const t = document.createElement("div");
  t.className = "toast" + (isError ? " error" : "");
  t.textContent = msg;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 4000);
}

function renderMarkdown(text) {
  if (window.marked) {
    try { return window.marked.parse(text); } catch (e) {}
  }
  // fallback: escape + keep line breaks
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML.replace(/\n/g, "<br>");
}

function escapeHtml(s) {
  const d = document.createElement("div");
  d.textContent = s;
  return d.innerHTML;
}

function highlight(el) {
  if (window.hljs) {
    el.querySelectorAll("pre code").forEach((b) => {
      try { window.hljs.highlightElement(b); } catch (e) {}
    });
  }
}

function scrollDown() {
  els.messages.scrollTop = els.messages.scrollHeight;
}

/* ---------------- session ---------------- */
async function initSession() {
  try {
    const res = await fetch(`${API}/api/session`, { method: "POST" });
    const data = await res.json();
    sessionId = data.session_id;
    els.modelBadge.textContent = "model: " + data.model;
  } catch (e) {
    toast("Could not reach the backend. Is the server running?", true);
  }
  // health -> show whether key is configured
  try {
    const h = await (await fetch(`${API}/api/health`)).json();
    if (h.api_key_configured) {
      els.keyBadge.textContent = "API key ✓";
      els.keyBadge.classList.add("ok");
    } else {
      els.keyBadge.textContent = "no API key";
      els.keyBadge.classList.add("bad");
    }
  } catch (e) {}
}

function resetChat() {
  els.messages.innerHTML = "";
  els.messages.appendChild(els.welcome);
  els.welcome.style.display = "";
  els.datasetList.innerHTML = '<li class="empty">No data loaded yet.</li>';
  hasData = false;
  initSession();
}

/* ---------------- file upload ---------------- */
async function uploadFile(file) {
  if (!file) return;
  if (!sessionId) { toast("No session yet, please wait...", true); return; }

  const fd = new FormData();
  fd.append("session_id", sessionId);
  fd.append("file", file);

  const li = document.createElement("li");
  li.className = "ds-item";
  li.innerHTML = `<div class="ds-name">${escapeHtml(file.name)}</div>
                  <div class="ds-meta">uploading…</div>`;
  if (els.datasetList.querySelector(".empty")) els.datasetList.innerHTML = "";
  els.datasetList.appendChild(li);

  try {
    const res = await fetch(`${API}/api/upload`, { method: "POST", body: fd });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.detail || "Upload failed");
    }
    const data = await res.json();
    li.innerHTML = `
      <div class="ds-name">${escapeHtml(data.name)}</div>
      <div class="ds-meta">
        <span class="ds-var">${data.var}</span>${data.rows.toLocaleString()} rows × ${data.cols} cols
      </div>`;
    li.onclick = () => showPreview(data);
    hasData = true;
    toast(`Loaded "${data.name}" as \`${data.var}\``);
    addSystemNote(`Loaded **${data.name}** → \`${data.var}\` (${data.rows.toLocaleString()} rows × ${data.cols} columns). Ask me anything about it!`);
  } catch (e) {
    li.querySelector(".ds-meta").textContent = "failed";
    toast(e.message, true);
  }
}

function showPreview(data) {
  els.previewTitle.textContent = `${data.name}  (${data.rows.toLocaleString()} × ${data.cols})`;
  let html = "<table><thead><tr>";
  data.columns.forEach((c) => {
    html += `<th>${escapeHtml(c.name)}<br><small style="color:#8b949e">${escapeHtml(c.dtype)}</small></th>`;
  });
  html += "</tr></thead><tbody>";
  data.preview.forEach((row) => {
    html += "<tr>" + row.map((v) => `<td>${v === null ? '<span style="color:#8b949e">∅</span>' : escapeHtml(String(v))}</td>`).join("") + "</tr>";
  });
  html += "</tbody></table>";
  els.previewBody.innerHTML = html;
  els.previewModal.classList.remove("hidden");
}

/* ---------------- chat ---------------- */
function addMessage(role, builder) {
  els.welcome.style.display = "none";
  const wrap = document.createElement("div");
  wrap.className = "msg " + role;
  const avatar = role === "user" ? "You" : "Σ";
  wrap.innerHTML = `<div class="avatar">${avatar}</div><div class="body"></div>`;
  const body = wrap.querySelector(".body");
  builder(body);
  els.messages.appendChild(wrap);
  scrollDown();
  return wrap;
}

function addSystemNote(md) {
  addMessage("assistant", (body) => {
    body.innerHTML = `<div class="role">Open Julius</div><div class="markdown">${renderMarkdown(md)}</div>`;
  });
}

function renderSteps(container, steps) {
  if (!steps || !steps.length) return;
  const wrap = document.createElement("div");
  wrap.className = "steps";
  steps.forEach((step, i) => {
    const isErr = !!step.error;
    const div = document.createElement("div");
    div.className = "step" + (i < steps.length - 1 ? " collapsed" : "");
    let inner = `
      <div class="step-head">
        <span class="dot ${isErr ? "err" : ""}"></span>
        <span>Step ${i + 1} · ran Python${isErr ? " (error, retried)" : ""}${step.charts && step.charts.length ? ` · ${step.charts.length} chart(s)` : ""}</span>
        <span class="chev">▾</span>
      </div>
      <div class="step-content">
        <pre class="code"><code class="language-python">${escapeHtml(step.code || "")}</code></pre>`;
    if (step.stdout) inner += `<pre class="output">${escapeHtml(step.stdout)}</pre>`;
    if (step.error) inner += `<pre class="output error">${escapeHtml(step.error)}</pre>`;
    if (step.charts && step.charts.length) {
      inner += `<div class="charts">` +
        step.charts.map((c) => `<img src="data:image/png;base64,${c}" alt="chart" />`).join("") +
        `</div>`;
    }
    inner += `</div>`;
    div.innerHTML = inner;
    div.querySelector(".step-head").onclick = () => div.classList.toggle("collapsed");
    wrap.appendChild(div);
  });
  container.appendChild(wrap);
  highlight(wrap);
}

async function sendMessage(text) {
  if (busy) return;
  text = (text || els.prompt.value).trim();
  if (!text) return;
  if (!sessionId) { toast("No session yet.", true); return; }

  els.prompt.value = "";
  els.prompt.style.height = "auto";
  setBusy(true);

  addMessage("user", (body) => {
    body.innerHTML = `<div class="role">You</div><div class="text"></div>`;
    body.querySelector(".text").textContent = text;
  });

  // assistant placeholder with typing indicator
  const aMsg = addMessage("assistant", (body) => {
    body.innerHTML = `<div class="role">Open Julius</div>
      <div class="status-line"><span class="typing"><span></span><span></span><span></span></span> analyzing…</div>`;
  });
  const aBody = aMsg.querySelector(".body");

  try {
    const res = await fetch(`${API}/api/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ session_id: sessionId, message: text }),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.detail || `Request failed (${res.status})`);
    }
    const data = await res.json();

    aBody.innerHTML = `<div class="role">Open Julius</div>`;
    renderSteps(aBody, data.steps);
    const ans = document.createElement("div");
    ans.className = "markdown";
    ans.innerHTML = renderMarkdown(data.answer || "*(no answer)*");
    aBody.appendChild(ans);
    highlight(ans);
    scrollDown();
  } catch (e) {
    aBody.innerHTML = `<div class="role">Open Julius</div>
      <div class="markdown" style="color:var(--danger)">⚠ ${escapeHtml(e.message)}</div>`;
  } finally {
    setBusy(false);
  }
}

function setBusy(v) {
  busy = v;
  els.send.disabled = v;
  els.prompt.disabled = v;
}

/* ---------------- events ---------------- */
els.send.onclick = () => sendMessage();
els.prompt.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendMessage(); }
});
els.prompt.addEventListener("input", () => {
  els.prompt.style.height = "auto";
  els.prompt.style.height = Math.min(els.prompt.scrollHeight, 180) + "px";
});

els.uploadArea.onclick = () => els.fileInput.click();
els.fileInput.onchange = (e) => { uploadFile(e.target.files[0]); e.target.value = ""; };
["dragenter", "dragover"].forEach((ev) =>
  els.uploadArea.addEventListener(ev, (e) => { e.preventDefault(); els.uploadArea.classList.add("drag"); }));
["dragleave", "drop"].forEach((ev) =>
  els.uploadArea.addEventListener(ev, (e) => { e.preventDefault(); els.uploadArea.classList.remove("drag"); }));
els.uploadArea.addEventListener("drop", (e) => {
  if (e.dataTransfer.files.length) uploadFile(e.dataTransfer.files[0]);
});

els.newChat.onclick = resetChat;
els.previewClose.onclick = () => els.previewModal.classList.add("hidden");
els.previewModal.onclick = (e) => { if (e.target === els.previewModal) els.previewModal.classList.add("hidden"); };

document.querySelectorAll(".example").forEach((b) =>
  b.addEventListener("click", () => sendMessage(b.textContent)));

/* ---------------- boot ---------------- */
initSession();
