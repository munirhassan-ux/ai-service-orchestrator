# Haazir — Technical Overview for Investors

## What We Built

Haazir is an AI-powered home services platform for Pakistan. A customer texts in Roman Urdu, English, or mixed language — and a network of autonomous AI agents handles the entire journey: understanding the request, finding the best provider, negotiating the price, tracking the job live, resolving disputes, and learning from every interaction. No human dispatcher is involved.

---

## Technology Stack

| Layer | Technology | Purpose |
|---|---|---|
| **AI / LLM** | Google Gemini 2.0 Flash & Flash-Lite | Intent parsing, match reasoning, dispute resolution, apology generation, auction decisions |
| **Backend** | Node.js + TypeScript + Express | REST API, agent orchestration, real-time state |
| **Mobile Frontend** | Flutter (Dart) | Dual-app: customer-facing chat + provider-facing job dashboard |
| **Data Storage** | JSON flat files (mock layer) | Bookings, contracts, disputes, provider ledger, sessions, invoices |
| **Geocoding** | OpenStreetMap Nominatim + static lookup table | Free, no API key required, covers all Islamabad sectors |
| **Real-time** | HTTP polling + in-memory notification queue | Live GPS simulation, push-style alerts to both apps |

---

## Architecture: The Orchestration Pipeline

Every customer message enters a single **Orchestrator** that routes it through a deterministic pipeline of specialist agents. Each agent does one job and hands off to the next. Every step is traced and persisted to a session log.

```
Customer Message
      │
      ▼
┌─────────────┐    PII redacted, abuse words blocked,
│  Guardrail  │ ── safety_strikes tracked per session
└──────┬──────┘
       │
       ▼
┌──────────────┐    Gemini Flash-Lite extracts: service_type,
│ IntentParser │ ── problem_description, location, time.
└──────┬───────┘    Asks clarifying questions in Roman Urdu
       │            until all 4 fields are collected.
       ▼
┌──────────────────┐    8-factor scoring: proximity, specialization,
│  ProviderMatcher │ ── reliability EWMA, cancellation_risk, capacity,
└──────┬───────────┘    availability slot, rating, price fit.
       │                Real-time slot conflict detection (±2h windows).
       ▼
┌──────────────────┐    CFP broadcast to top 5 Provider Agents →
│ NegotiationEngine│ ── bids collected → CustomerAgent scores utility →
└──────┬───────────┘    accept or counter → signed Contract locked.
       │
       ▼
┌──────────────┐    Booking created, contract linked,
│   Booking    │ ── provider Flutter app auto-launched,
│   Simulator  │    GPS simulation begins.
└──────┬───────┘
       │
       ├── SLA Monitor (background): warns at 25 min, auto-cancels at 50 min
       ├── Recovery Agent: if cancelled → apology + re-auction
       ├── Dispute Agent: evidence assembly + Gemini reasoning + auto-resolution
       └── Reliability Engine: EWMA score updates on every lifecycle event
```

---

## The Agents — What Each One Does

### 1. Guardrail (Input & Output Safety)

Every message in and out passes through a two-way sanitizer. On input, it regex-strips Pakistani phone numbers (`03xx-xxxxxxx`), CNICs (13-digit national IDs), emails, and house numbers — replacing them with placeholder tokens (`[PHONE_1]`) so Gemini never sees real PII. It also normalizes leet speak (`h4ramzada` → `haramzada`) to catch abuse. On output, it scans Gemini's reply before it reaches the client and blocks any echoed PII. Repeat abusers accumulate `safety_strikes`; 3 strikes triggers a 24-hour account ban.

**Thought process:** Pakistan has stringent emerging data privacy laws and a mobile-first market where users habitually share phone numbers in chat. We needed a zero-trust layer that scrubs PII before it ever touches the LLM — not after.

---

### 2. Intent Parser (Gemini Flash-Lite)

Accepts Roman Urdu / English / mixed input and extracts a structured JSON: service type, problem description, location, urgency, time, budget sensitivity, and job complexity. It follows a strict 4-step conversation script — it won't proceed to matching until all four required fields are collected. It recognizes Pakistani speech patterns: `"pambr"` → plumber, `"paani leak ho raha"` → plumber, `"bilkul kaam nahi"` → high urgency. It responds in Roman Urdu by default, adjusts time questions based on current PKT time, and keeps clarification questions under 15 words.

**Thought process:** Pakistani users don't speak in service-app vocabulary. They type the way they text friends. We trained the prompt on symptom-to-service mappings and Roman Urdu misspellings rather than relying on keywords, so the agent understands intent even when the input is messy.

---

### 3. Provider Matcher (Deterministic + Gemini Reasoning)

Scores every provider in the database against the parsed intent using **8 weighted factors**:

| Factor | Weight | Logic |
|---|---|---|
| Travel Time | 15% | Haversine distance → estimated travel minutes |
| Availability Match | 15% | Exact slot = 100, delayed = scaled, offline = 40 |
| Specialization | 20% | Exact match = 100, alias = 60, generic = 30 |
| Reliability (EWMA) | 15% | Live composite score (see Reliability Engine) |
| Review Sentiment | 10% | Rating/5 × 100, −20% penalty if < 4.3 |
| Price Fit | 10% | Lower rate scores higher; reduced to 5% for flexible budgets |
| Cancellation Risk | 10% | (1 − risk) × 100 |
| Capacity | 5% | Available slots / total capacity |

It checks real-time booking data to detect slot conflicts (±2 hour windows) and filters out providers in cooldown. If fewer than 3 providers qualify, it falls back to waitlisted options flagged transparently. Gemini writes a 2-sentence human-readable explanation of why the top provider was chosen.

**Thought process:** A simple nearest-provider or highest-rated sort produces bad outcomes in Pakistan — providers often have specializations within a category (e.g., split AC vs. window AC), and a high-rated provider who cancels frequently is worse than a slightly lower-rated reliable one. The composite score captures the real trade-offs.

---

### 4. A2A Negotiation Engine (Agent-to-Agent Auction)

This is the most architecturally novel component. Rather than presenting providers to the customer and waiting for a choice, **two classes of AI agents negotiate on their behalf in real time**:

**Provider Agents** (deterministic, zero-latency): Each of the top 5 providers has a negotiation policy: minimum acceptable price, surge appetite, auto-accept threshold, max travel radius, and counter strategy (hold / meet-in-middle / small concession). When the Orchestrator broadcasts a Call for Proposals (CFP) with the job spec, each Provider Agent independently evaluates it and submits a bid (price, ETA, confidence) or rejects with a reason.

**Customer Agent** (Gemini-assisted): Scores all incoming bids using a utility function weighted 40% reliability, 35% price, 25% ETA. If the best bid is within budget, it accepts immediately (Round 1). If over budget, it sends counter-offers to the top 2 providers (Round 2) at 95% of the ceiling — providers respond based on their floor price and counter strategy. The winning bid is locked into a signed **Contract** with a full CFP log and event log.

**Thought process:** The A2A model solves a real marketplace problem: if you show the customer a list, they spend time deciding and providers go stale. If you auto-assign, customers feel they lost agency. A2A gives customers the best available price automatically — the Customer Agent is their representative — while providers compete fairly on merit. This also creates an auditable contract record for every booking, which feeds the dispute resolution system.

---

### 5. Booking Simulator + GPS Tracking

Once a contract is signed, a booking is created and the provider's Flutter app is auto-launched in a browser window. The booking follows a state machine:

```
PENDING_PROVIDER → ACCEPTED → ARRIVING → ARRIVED → IN_PROGRESS → COMPLETED
```

GPS simulation uses the Haversine formula to move the provider 75% of the remaining distance per step, triggering `ARRIVED` when within 50 meters. Both apps receive real-time notifications at each transition.

---

### 6. SLA Monitor (Background Agent)

A background interval process (runs every 2 minutes) watches all active bookings. If a provider accepts but doesn't move for **25 minutes**, it sends an agent-to-agent SLA warning message and notifies the customer. At **50 minutes** of inactivity, it auto-cancels the booking, fires a `no_show` event to the Reliability Engine (−25 points), and notifies the customer. Scheduled bookings that pass their appointment time by 20 minutes without a provider update are also auto-cancelled.

**Thought process:** In Pakistan's gig economy, provider ghosting after acceptance is a real problem. Rather than waiting for the customer to complain, the platform acts proactively — punishing the provider's score and freeing the customer to rebook.

---

### 7. Recovery Agent (Gemini)

When a cancellation occurs, the Recovery Agent doesn't just silently reassign — it:

1. **Classifies the cause**: provider emergency, serial no-show, or repeated canceller
2. **Selects compensation**: priority re-match (no surge), visit fee waiver (Rs. 150), or honour-original-price guarantee
3. **Generates a warm empathetic apology** in the customer's language via Gemini
4. **Re-runs the full A2A auction** excluding all previously tried providers
5. Returns the new booking with the apology text and compensation offer

**Thought process:** A cold "your provider cancelled, new booking created" message destroys trust. The Recovery Agent treats cancellations as customer relationship moments — the language, the compensation, and the speed of replacement all matter.

---

### 8. Dispute Resolution Agent (Evidence-Grounded + Gemini)

When a customer raises a dispute, the agent assembles an evidence bundle from multiple sources: the signed contract, the booking's state history, GPS timestamps, checklist completion percentage, the A2A CFP log, and the overcharge amount. It first tries a fast rule-based resolution; if the case is ambiguous, it passes the evidence bundle to Gemini with a strict resolution menu (`full_refund`, `partial_refund_N`, `service_credit_N`, `redo_at_no_cost`, `provider_warning`, `dismiss`, `escalate`). Confidence ≥ 0.65 auto-resolves; below that it escalates to human review.

No-shows confirmed by state history (provider never reached `ARRIVED` status) trigger auto-refund + Recovery Agent re-dispatch. Disputes on live jobs are held in `awaiting_completion` state and resolved when the job ends.

**Thought process:** "He-said-she-said" disputes are unresolvable without evidence. By capturing the full job lifecycle in a structured state machine — and linking it to the signed contract — we have objective data to reason over. Gemini's role is judge, not jury: it interprets the evidence against policy rules rather than making subjective calls.

---

### 9. Reliability Engine (EWMA Score)

Every provider has a live **0–100 reliability score** computed as a weighted EWMA (exponentially weighted moving average) across 5 dimensions:

```
30% × on_time_rate
25% × completion_rate
20% × recency_weighted_rating
15% × (1 − cancellation_rate)
10% × dispute_outcome_factor
```

Events update the score immediately:

| Event | Score Delta |
|---|---|
| Job completed on time | +3 |
| Job completed late | +1 |
| Dispute won | +4 |
| Late arrival | −6 |
| Dispute lost (severe) | −12 |
| Cancel after accept | −15 |
| No-show | −25 |

Providers who drop below score 40 or accumulate 2+ no-shows are auto-placed in a **4-hour cooldown** (`availability_status = offline`). This score feeds directly into the ProviderMatcher's ranking.

**Thought process:** Static ratings are slow-moving and gameable. An EWMA score means a provider who was great 6 months ago but has been unreliable lately ranks lower than their star rating suggests. The cooldown mechanism protects customers from being matched to providers who are currently in a bad streak.

---

### 10. Preference Engine

After every completed booking, the system updates the customer's preference profile: last service type, booking history count, preferred time slots, and budget patterns. On the next session, the greeting is personalized and the ProviderMatcher adjusts budget weights accordingly.

---

## Frontend: Two Flutter Apps, One Backend

The platform runs **two separate Flutter web apps** from a single backend:

- **Customer App**: Conversational chat UI, real-time GPS map tracking, booking status card, dispute filing, invoice/summary screen
- **Provider App**: Job listings dashboard, accept/decline/checklist controls, GPS tracking view, earnings history

When a booking is confirmed, the backend auto-spawns a new browser window serving the Provider App pre-scoped to that booking ID — the provider sees their job card appear in real time without any manual registration step.

---

## Key Design Principles

**1. Every agent has a fallback.** Gemini calls are wrapped with deterministic rule-based fallbacks. If the LLM is unavailable, the system degrades gracefully — the Dispute Agent uses rule tables, the Recovery Agent uses a hardcoded apology template.

**2. PII never touches the LLM.** Guardrails strip Pakistani identifiers before every Gemini call and scan outputs before they reach the client. Redactions are auditable per session.

**3. Agent communication is traceable.** Every agent call, reasoning string, and decision is persisted to a session trace file. The booking detail screen surfaces the A2A negotiation trace (who bid, what price, why they won) to both customer and provider.

**4. The provider score is a live instrument.** Rather than periodic reviews, every lifecycle event — on-time arrival, cancellation, dispute outcome — updates the provider's composite score in real time. This score directly affects their ranking and visibility in future auctions.

**5. Language is first-class.** The platform speaks Roman Urdu natively — not as a translation layer but as the default. The IntentParser, SLA Monitor, Recovery Agent, and Dispute Agent all produce Roman Urdu text. This is deliberate: most Pakistani mobile users type in Roman Urdu, not English or script Urdu.

---

## Summary

Haazir is built on a **multi-agent architecture where Gemini acts as reasoning engine, not orchestrator**. Deterministic algorithms handle ranking, pricing, and scoring (fast, auditable, consistent). Gemini handles the things that require language and judgment: understanding messy human input, writing empathetic messages, and reasoning over ambiguous evidence. The two layers are cleanly separated so either can be swapped or upgraded independently.

---

---

# Anticipated Investor Technical Questions

## Architecture & Scalability

**Q: You're using JSON flat files for storage. What's the production database plan?**
> The JSON layer is a deliberate mock for the prototype — it mirrors what a production schema would look like. The migration path is straightforward: each JSON structure maps directly to a PostgreSQL table (bookings, contracts, disputes, providers, sessions, reliability_ledger). The agent code reads/writes through thin repository functions, so swapping the storage layer requires changing only those functions. We chose this approach to move fast in the prototype without cloud infrastructure costs.

**Q: How does this scale when you have thousands of concurrent bookings?**
> The Orchestrator is stateless — session state lives in the session store, not in memory. Each incoming request creates an independent pipeline run. The bottleneck today is the flat file I/O; moving to Postgres with connection pooling and adding a Redis layer for the notification queue handles the transition to production scale. The agent logic itself (matching, negotiation, scoring) is CPU-bound and horizontally scalable.

**Q: The SLA Monitor runs on a setInterval every 2 minutes inside the server process. What happens when you have multiple server instances?**
> Good catch. In a multi-instance production deployment, the SLA Monitor needs to move to a distributed job scheduler (e.g., BullMQ with Redis, or a dedicated cron worker). The current design is correct for a single-instance deployment. The fix is isolating the monitor into its own worker service that holds a distributed lock — the agent logic itself doesn't change.

---

## AI & Agent Design

**Q: Why Gemini instead of OpenAI / Claude?**
> Gemini 2.0 Flash offers competitive performance with lower cost per token and generous rate limits, which matters at high booking volume. More practically, the Google Generative AI SDK has a `responseMimeType: "application/json"` mode that enforces structured output natively — we don't need prompt engineering tricks to get valid JSON out of the LLM. The architecture is LLM-agnostic: swapping to another model requires changing the model instantiation line in each agent, not the agent logic.

**Q: What happens when Gemini halluccinates or returns malformed JSON?**
> Every Gemini call is wrapped in a try/catch with a deterministic fallback. The IntentParser falls back to a low-confidence structured object that triggers clarification. The DisputeAgent falls back to its rule table. The ProviderMatcher falls back to a hardcoded reasoning string. The Recovery Agent falls back to a template apology. No agent fails hard — the worst case is a slightly less intelligent response, not a broken flow.

**Q: How do you prevent the IntentParser from being prompt-injected?**
> The IntentParser only returns a structured JSON schema — it cannot produce free text that reaches the client. PII is stripped from the input before it hits the LLM. The output is parsed as JSON and validated against a TypeScript interface; unexpected fields are ignored. The system prompt constrains the model to only extract the four required fields, and the output safety check on the Orchestrator layer catches any stray PII that leaked through.

**Q: The A2A negotiation sounds like it adds latency. How long does it take?**
> The negotiation pipeline runs in roughly 1–2 seconds total. Provider Agents are fully deterministic (zero LLM calls), so all 5 bids are collected in milliseconds. The Customer Agent makes one Gemini call for the reasoning string — that's the only LLM call in the whole auction. The rest is pure computation. The slowest part is usually geocoding the customer's location (100–300ms on a Nominatim lookup; instant on a static cache hit).

**Q: Can providers game the system by setting artificially low prices to win auctions and then overcharging on-site?**
> This is addressed at multiple layers. First, prices are set by the provider's negotiation policy (floor price, base rate), not entered per-booking — so a provider can't selectively underbid. Second, the final price is locked in a signed Contract with a full audit trail. Third, the Dispute Agent compares the charged amount against the contract's `agreed_price` field — if there's a delta with a completed checklist, it auto-proposes a refund. Fourth, price manipulation would show up as recurring overcharge disputes, which penalize the reliability score over time.

---

## Product & Market

**Q: Why build A2A negotiation instead of just showing a list of providers?**
> List-based selection has two problems in the Pakistani home services context: decision fatigue (customers don't know how to compare providers) and provider staleness (by the time a customer picks, the top provider may already be booked). The A2A auction resolves both — it picks the best available provider at the best price, instantly, and surfaces the reasoning so the customer understands why. It also creates a competitive dynamic that incentivizes providers to price fairly.

**Q: Roman Urdu support — how deep does it go? Is it just the UI or the AI too?**
> The AI itself speaks Roman Urdu. The IntentParser's system prompt is written around Roman Urdu patterns, misspellings, and code-switching. Clarification questions, SLA warnings, recovery apologies, and dispute messages are all generated in Roman Urdu. There is also a `roman_urdu_map.json` lookup table for pre-processing common Pakistani spellings before the LLM sees them — this reduces hallucination and speeds up service type detection.

**Q: What's your moat? Couldn't an incumbent like Bykea or Rozee replicate this?**
> The moat is the reliability data flywheel. Every booking generates EWMA score updates that make the matching engine progressively more accurate. The A2A negotiation contracts create a price history that lets the system detect anomalies and enforce fairness. A new entrant copying the UI has none of this data. The second moat is the Roman Urdu NLU — we've invested in prompt engineering for Pakistani speech patterns that a generic LLM wrapper can't match without the same iteration.

---

## Security & Compliance

**Q: How are you handling data privacy for Pakistani users?**
> PII is stripped at the API boundary before any LLM call — phone numbers, CNICs, emails, and house numbers are replaced with placeholder tokens. The redaction log is auditable per session. Provider agents only receive the job area, not the customer's exact address. We are building toward PDPA (Pakistan's Personal Data Protection Act) compliance — the guardrail architecture is designed to meet its requirements.

**Q: What's the abuse prevention model?**
> Three layers: (1) per-message leet-speak-normalized profanity detection with session-level strike counting; (2) session lock after 3 in-session strikes; (3) cross-session cumulative strike tracking per `customer_id` with a 24-hour account ban at 10 lifetime strikes. The ban expiry time is communicated to the user so they know when the block lifts. Provider-side abuse (repeated cancellations, no-shows) is handled through the reliability engine's cooldown mechanism.

---

## Investment-Specific Questions

**Q: How much does the AI cost to run per booking?**
> The current Gemini call breakdown per booking: 1 IntentParser call (Flash-Lite, cheap), 1 ProviderMatcher reasoning call (Flash), 1 CustomerAgent reasoning call (Flash), optionally 1 DisputeAgent call (Flash). At Gemini 2.0 Flash pricing, the AI cost per completed booking is estimated under $0.01. The architecture deliberately minimizes LLM calls — Provider Agents are fully deterministic, the scoring algorithms are pure computation, and static lookups handle geocoding for all major Islamabad sectors.

**Q: What does the road to production look like technically?**
> Three phases: (1) **Infrastructure swap** — replace JSON storage with PostgreSQL, move notifications to Firebase/WebSockets, add proper auth (JWT + refresh tokens); (2) **Provider onboarding** — build provider registration flow, KYC document upload, and negotiation policy configuration UI; (3) **Scale hardening** — distributed SLA monitor, Redis session cache, rate limiting on the orchestration endpoint, and a dashboard for operations to monitor agent traces in real time. The core agent logic requires no changes for production — it's the infrastructure layer that needs upgrading.
