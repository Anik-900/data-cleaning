# Upwork Proposal Templates — Ready-to-Use

Five proposal templates calibrated for the highest-converting freelance niches in 2026.
Replace `[brackets]` with real values before sending.

**Universal rules I'm following in all five:**
1. First 2 lines = specific, evidence-based match (clients only read the first 2 lines).
2. Embed proof: live demo URL + Loom video + GitHub.
3. Specific 3-4 step plan (separates you from generalists).
4. Engagement question at the end (forces a reply).
5. Disclose rate early (saves both sides' time).
6. Length: 150-220 words.

---

## ✉️ Proposal #1 — Marketing Data Cleaning + Analytics

**Job pattern:** "Need Python expert to clean messy CSV marketing data + generate insights"

```
Hi [Client Name],

I just built almost exactly this — a Python tool that cleans messy marketing 
campaign CSVs (negative spends, missing CPC, outliers) and auto-generates 
3 actionable insights using GPT-4.

Live demo: [your-streamlit-url]
Source: [github-link]
60-sec walkthrough: [loom-link]

For your project specifically, here's how I'd handle it:
1. Audit your CSV — flag negative values, missing fields, outliers (IQR method)
2. Apply cleaning rules you approve (we'll do a quick call to align)
3. Deliver cleaned CSV + a one-page AI-generated insight report
4. Optional: Streamlit dashboard for repeat use

Timeline: 2-3 days for a one-time clean, 5-7 days if you want the dashboard.
Rate: $25/hr (currently building 5-star reviews; my market rate is $50+).

Quick question: Are you cleaning this data once, or do you receive new exports 
weekly/monthly that need the same treatment? That changes my recommendation.

[Your Name]
```

---

## ✉️ Proposal #2 — Custom AI Chatbot / RAG

**Job pattern:** "Build a chatbot trained on our company documents (PDFs, manuals)"

```
Hi [Client Name],

I built a production RAG system last week that does exactly this — upload PDFs, 
ask questions, get cited answers with page numbers.

Live demo: [rag-streamlit-url]   (try uploading any PDF)
GitHub: [repo-link]
Architecture explanation (90-sec): [loom-link]

It uses:
• Hybrid search (vector + keyword) for higher accuracy than basic ChatGPT plugins
• Citation tracking (every answer shows source + page)
• Cost tracking (~$0.003 per query)

For your use case, I'd:
1. Set up the ingestion pipeline for your [PDF/DOCX/website] documents
2. Customize the system prompt for your domain (tone, restrictions)
3. Deploy to Streamlit Cloud / your own server / Slack as a bot
4. Provide a 30-min handover call + 2 weeks of support

Pricing: $400 (basic — 1 collection, ~50 docs) up to $1,200 (multi-user, 
auth, integration with your Slack/web).

One question: Roughly how many documents and total pages are we talking about? 
And do you need the bot inside Slack/Teams or as a standalone web app?

[Your Name]
```

---

## ✉️ Proposal #3 — Workflow Automation (n8n / Make.com / Zapier)

**Job pattern:** "Need automation expert to connect [App A] to [App B] with AI processing"

```
Hi [Client Name],

I've automated this exact pattern (data flowing between apps + AI processing 
in the middle) for 3 different setups recently.

Most likely architecture for you:
[Source App] → Webhook → n8n / Make.com → OpenAI processing → [Destination App]

Example I built last month:
• Trigger: New customer support email arrives
• AI step: GPT-4o classifies (urgent/normal/spam) + drafts a reply
• Output: Slack notification + draft auto-saved in Gmail

Walkthrough video: [loom-link]

For your project, I'll need 10 minutes to confirm:
1. What's the trigger event?
2. What apps are we connecting? (so I can confirm available APIs/nodes)
3. Cloud-hosted (Make.com — easy) or self-hosted (n8n — cheaper long-term)?

Typical delivery: 3-5 days depending on complexity.
Rate: $30/hr or fixed $250-$800 depending on scope.

Happy to jump on a 15-min call if useful — I'll come prepared with a draft 
flow diagram for your specific use case.

[Your Name]
```

---

## ✉️ Proposal #4 — OpenAI / GPT API Integration

**Job pattern:** "Need developer to integrate ChatGPT into our [app/website/process]"

```
Hi [Client Name],

Read your post — looks like you need [their specific use case rephrased]. 
I've shipped 4 similar OpenAI integrations in the last 60 days.

Beyond just "calling the API", here's what most clients miss and why their 
GPT integration breaks in production:

1. Cost runaway: Without token limits and caching, $20/day can become $500/day
2. Hallucinations: Without function calling or structured outputs, GPT 
   invents data
3. Rate limits: Without retry/backoff logic, traffic spikes break the app
4. Prompt versioning: Without testing prompts on edge cases, accuracy drops

I handle all four by default. Examples in my GitHub: [link]
60-sec demo of a recent integration: [loom-link]

For your project, here's the rough plan:
• Day 1: Setup + first working version with your data
• Day 2-3: Refinement, error handling, cost guardrails
• Day 4: Tests + handover documentation

Fixed price: $400-$900 depending on complexity. Rate if hourly: $30/hr.

What's your monthly query volume estimate? That changes whether we use 
GPT-4o-mini ($) or GPT-4o ($$$).

[Your Name]
```

---

## ✉️ Proposal #5 — Data Analysis + Dashboard

**Job pattern:** "Need someone to analyze our [sales/marketing/operational] data and build a dashboard"

```
Hi [Client Name],

I run a small portfolio of marketing analytics work, including a recent 
project where I cleaned 1,200 messy campaign rows + built a dashboard with 
GPT-generated insights.

Live example: [streamlit-demo]
GitHub: [link]
2-min walkthrough: [loom-link]

For your data, I'd deliver:
1. Cleaned dataset (deduped, missing values handled, outliers flagged)
2. Exploratory analysis — top performers, anomalies, trends
3. Interactive dashboard in Streamlit or Looker Studio (your choice)
4. AI-generated executive summary — 5 bullets your CEO can read in 
   30 seconds
5. Loom walkthrough — so anyone on your team can use it

Tech: Python, pandas, numpy, Plotly, OpenAI for the insight layer.

Timeline: 4-6 days. Price: $350-$900 depending on data size and dashboard 
complexity.

Quick questions before I quote final:
• How many rows / what time range?
• Are you connecting to a live source (Sheets, Postgres, BigQuery) or working 
  from a static export?

I can send a sample dashboard mockup within 24 hours if you're interested.

[Your Name]
GitHub: [link] | LinkedIn: [link]
```

---

## 📈 Tracking Spreadsheet (Google Sheets template)

| Date | Job link | Niche | Sent at | Reply? | Call? | Closed? | $ |
|------|----------|-------|---------|--------|-------|---------|---|
|      |          |       |         |        |       |         |   |

Goal: 5 proposals/day → expect 5–15 replies/100 → 1–2 closed clients/100.

---

## 🎯 Cold Outreach (LinkedIn DM + Email)

### LinkedIn DM template

```
Hi [First Name], saw you run [Company]. Quick one — are you still doing 
campaign performance reports manually in Sheets?

I built a tool that auto-cleans + generates AI insights from any marketing 
CSV in 30 seconds: [demo link]

If useful, happy to set it up free for your team — would love a testimonial 
in return.

Either way, big fan of [something specific from their profile].
```

### Cold email template

**Subject:** `Quick idea for [Company]'s campaign reporting`

```
Hi [First Name],

Noticed [Company] runs paid campaigns on Meta + TikTok. Most agencies I work 
with spend 6-8 hours/week just cleaning the export data before insights.

I built a Python + AI tool that does it in 30 seconds: [demo URL]

Would it be useful if I ran your last month's campaign data through it (free) 
and sent you a 5-min Loom showing the insights?

If yes, just reply with a CSV — I'll send results within 24 hours.

[Name]
```

Realistic response rate: 5–10%. 100 DMs ≈ 5–10 conversations ≈ 1–2 paid clients.
