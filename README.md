# Hazir — AI Service Orchestrator for Pakistan's Informal Economy

> **Google Antigravity Hackathon — Challenge 2**
> App Name: **Hazir** (حاضر — meaning "Present" / "Ready")
> Repo: [github.com/munirhassan-ux/ai-service-orchestrator](https://github.com/munirhassan-ux/ai-service-orchestrator)
> Stack: Flutter (Dart 52.9%) · TypeScript/Node.js (35.1%) · Google Gemini via Antigravity

---

## Table of Contents

1. [What is Hazir](#1-what-is-hazir)
2. [Architecture Overview](#2-architecture-overview)
3. [User Flow](#3-user-flow)
4. [Antigravity Workflow](#4-antigravity-workflow)
5. [Agent Pipeline](#5-agent-pipeline)
6. [Provider Dataset Schema](#6-provider-dataset-schema)
7. [Customer Dataset Schema](#7-customer-dataset-schema)
8. [Job Schema](#8-job-schema)
9. [Matching Algorithm — 8 Factors](#9-matching-algorithm--8-factors)
10. [Job Status State Machine](#10-job-status-state-machine)
11. [Push Notification Events](#11-push-notification-events)
12. [APIs and Tools](#12-apis-and-tools)
13. [Assumptions](#13-assumptions)
14. [Cost and Latency Analysis](#14-cost-and-latency-analysis)
15. [Baseline Comparison](#15-baseline-comparison)
16. [Privacy Note](#16-privacy-note)
17. [Limitations](#17-limitations)
18. [How to Run](#18-how-to-run)

---

## 1. What is Hazir

Hazir is an agentic AI system that automates the complete lifecycle
of a home service request in Pakistan's informal economy — from a
natural-language message typed in any language to a matched,
confirmed, tracked, and rated service booking.

### The Problem

Pakistan's informal service sector — plumbers, electricians, AC
technicians, carpenters, cleaners — operates almost entirely through
WhatsApp messages, phone calls, and word-of-mouth referrals. This
creates four structural failures every day:

| Problem | Real-world consequence |
|---|---|
| No price transparency | Every quote is an unstructured negotiation |
| No trust signals | No ratings, no track record, no accountability |
| No scheduling | "I'll come when I can" is the standard answer |
| No dispute resolution | No paper trail, no recourse when things go wrong |

### The Solution

Hazir replaces this with a single conversational chat interface where
the customer describes their problem and the AI orchestrator:

- Understands the request in English, Urdu, or Roman Urdu
- Finds and ranks the 3 best available providers using 8 factors
- Confirms the booking and notifies the provider via push notification
- Tracks the provider's simulated location in real time
- Automatically detects arrival based on GPS coordinates
- Sends timely reminders and status updates to both parties
- Collects a star rating on completion and updates provider scores

Both customer and provider experience the app as a conversational
chat interface. There are no forms and no complex navigation — every
decision happens as a message in the chat thread.

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         HAZIR SYSTEM                            │
│                                                                 │
│  ┌──────────────────┐    REST/HTTP    ┌───────────────────────┐ │
│  │   Flutter App    │◄──────────────►│   Express Backend     │ │
│  │   /frontend/     │                │   TypeScript / Node   │ │
│  │                  │                │   /backend/src/       │ │
│  │  Customer Chat   │                └──────────┬────────────┘ │
│  │  Provider Chat   │                           │              │
│  │  Job Tracking    │                ┌──────────▼────────────┐ │
│  │  Bookings Tab    │                │     Orchestrator      │ │
│  │  Alerts Tab      │                │     orchestrator.ts   │ │
│  │  Profile Tab     │                └──────────┬────────────┘ │
│  └──────────────────┘                           │              │
│                                ┌────────────────┼───────────┐  │
│                                │                │           │  │
│                         ┌──────▼──┐     ┌───────▼──┐  ┌────▼─┐│
│                         │ Intent  │     │ Provider │  │Book- ││
│                         │ Parser  │     │ Matcher  │  │ing   ││
│                         └──────┬──┘     └───────┬──┘  │Simu- ││
│                                │                │     │lator ││
│                                └────────────────┘     └──────┘│
│                                           │                    │
│                               ┌───────────▼──────────────────┐ │
│                               │   Google Gemini 3.1 Pro      │ │
│                               │   via @google/genai SDK      │ │
│                               │   Orchestrated by            │ │
│                               │   Google Antigravity         │ │
│                               └──────────────────────────────┘ │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  JSON Data Layer  /backend/data/                         │  │
│  │  mock_providers.json     — 20 service providers          │  │
│  │  mock_bookings.json      — job records and status        │  │
│  │  mock_schedule.json      — slot reservation registry     │  │
│  │  industry_standards.json — Pakistan market price ranges  │  │
│  │  roman_urdu_map.json     — language signal mapping       │  │
│  │  sessions.json           — active customer sessions      │  │
│  │  agent_traces/           — per-session Antigravity logs  │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Technology Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart) — `/frontend/` |
| Backend | TypeScript, Express.js, Node.js — `/backend/` |
| AI Model | Google Gemini 3.1 Pro |
| AI SDK | `@google/genai` npm package |
| Orchestration | Google Antigravity |
| Push Notifications | Flutter `local_notifications` package |
| Location Simulation | Haversine-based coordinate interpolation |
| Data Store | JSON flat files (no external database for demo) |

---

## 3. User Flow

### Customer Flow

```
1. Open app
   └── Default persona: Customer (toggle on)
       └── Chat screen opens with AI greeting

2. Customer describes their problem
   ├── What service is needed
   ├── Location (longitude + latitude or area name)
   ├── Preferred time to get it resolved
   └── Details about the problem
       (collected conversationally — one question at a time)

3. AI presents 3 best matches
   Ranked by: travel time, availability, service specialisation,
   on-time score, review sentiment, rate, cancellation risk, capacity
   └── Customer reads each provider card in chat

4a. Customer selects a provider
    └── Go to step 5

4b. Customer asks for more options
    └── Go back to step 3 (next batch of ranked providers)

5. AI confirms booking
   └── Sends push notification to service provider
   └── Sends confirmation message to customer in chat

6. Reminder sent to customer (1 hour before provider arrival)
   └── Push notification: "Provider arriving in 1 hour"

7a. Provider arrives and completes job
    └── Provider marks job done
    └── Customer receives star rating form in chat
    └── Rating recalculates provider scores

7b. Provider cancels before arrival
    └── Push notification to customer: "Provider cancelled"
    └── AI apologises in chat
    └── AI restarts search — presents 3 new best matches
    └── Go back to step 3
```

### Service Provider Flow

```
1. Receive push notification about incoming job
   └── Default persona: Provider (toggle on)
   └── Tap notification → opens app to job details

2. View full job details
   └── Booking ID, customer name, service type,
       problem description, time to arrive,
       estimated time to complete, full charges breakdown

3a. Provider accepts
    └── Push notification to customer: "Provider accepted"
    └── Job status → Accepted

3b. Provider cancels
    └── Cancellation risk score increases
    └── Customer notified and search restarts
    └── Job status → Cancelled

4. Simulated travel
   └── Provider's longitude + latitude interpolated toward
       customer's longitude + latitude over time
   └── System detects arrival when coordinates match
   └── Job status → Arrived (auto-detected)
   └── Push notification to customer: "Provider is on the way"
       (sent when status moves to Arriving, 1 hour before slot)

5. Job in progress
   └── Job status → In Progress

6. Job completion
   └── Push notification to provider (after estimated completion time):
       "If you have completed this job, please mark as done"
   └── If provider does not respond in 1 hour:
       job is automatically marked as done
   └── Job status → Completed

7. Post-completion
   └── Scores recalculated for provider
   └── Star rating form sent to customer
```

---

## 4. Antigravity Workflow

Antigravity is the core orchestration platform for Hazir. It is not
used superficially — it controls the entire reasoning and execution
pipeline for every agent call in the system.

### How Antigravity is Used

**Agent Orchestration**
Antigravity manages the sequential execution of all agents in the
pipeline: IntentParser → ProviderMatcher → BookingSimulator →
LocationTracker → ScoreUpdater. Each agent is a structured reasoning
step within Antigravity's planning framework.

**Gemini Model Access**
Every agent that requires language understanding or decision-making
calls Google Gemini 3.1 Pro through the `@google/genai` SDK managed
by Antigravity. This includes: multilingual intent extraction,
provider ranking rationale generation, and conversational response
generation. No other LLM is used anywhere in the system.

**Plan Mode — Workplan Generation**
Antigravity's Plan mode was used at the start of each development
session to generate a structured workplan and task execution order
before code was written. These workplans form part of the submission
artifacts alongside the agent trace logs.

**Trace Log Generation**
Every orchestration session produces a structured JSON trace file
at `/backend/data/agent_traces/[session_id].json`. This is the
primary submission artifact for the hackathon. It captures every
agent step, every Gemini call, every decision and fallback, and the
final outcome — exportable via `GET /api/trace/export/:session_id`.

### Sample Agent Trace Entry

```json
{
  "session_id": "sess_1716123456789",
  "user_input": "AC kaam nahi kar raha, kal subah G-13",
  "started_at": "2025-05-16T10:00:00.000Z",
  "completed_at": "2025-05-16T10:00:09.882Z",
  "total_duration_ms": 9882,
  "steps": [
    {
      "step": 1,
      "agent": "IntentParser",
      "model": "gemini-3.1-pro",
      "prompt_summary": "Extract intent from: 'AC kaam nahi kar raha, kal subah G-13'",
      "gemini_decision": "ac_repair, G-13, tomorrow morning, urgency: high, roman_urdu",
      "confidence": 0.94,
      "input": { "user_input": "AC kaam nahi kar raha, kal subah G-13" },
      "output": {
        "service_type": "ac_repair",
        "problem_type": "ac_not_cooling",
        "location": "G-13",
        "urgency": "high",
        "preferred_time": "tomorrow_morning",
        "language": "roman_urdu",
        "confidence": 0.94,
        "clarification_needed": false
      },
      "duration_ms": 1240,
      "fallback_triggered": false
    },
    {
      "step": 2,
      "agent": "ProviderMatcher",
      "model": "gemini-3.1-pro",
      "gemini_decision": "Top 3 selected. Ali AC Services ranked first: 1.2km, 94% on-time, intermediate skill, low cancellation risk.",
      "input": { "service": "ac_repair", "location": "G-13", "urgency": "high" },
      "output": {
        "providers_returned": 3,
        "top_provider": "Ali AC Services",
        "composite_score": 0.81
      },
      "duration_ms": 2340,
      "fallback_triggered": false
    },
    {
      "step": 3,
      "agent": "BookingSimulator",
      "model": null,
      "gemini_decision": "Deterministic — no model call",
      "output": {
        "booking_id": "BK-20250516-0001",
        "status": "pending_provider",
        "slot_locked": true,
        "notification_sent": true
      },
      "duration_ms": 18,
      "fallback_triggered": false
    }
  ],
  "final_outcome": "booked",
  "booking_id": "BK-20250516-0001",
  "providers_tried": ["p001"],
  "restart_count": 0
}
```

### Fallback Events Logged by Antigravity

| Event | Description |
|---|---|
| `provider_cancelled` | Provider cancelled after acceptance — search restarted |
| `provider_skipped` | Provider excluded from ranking and why |
| `warm_restart` | Silent re-route to next batch — session data preserved |
| `slot_soft_locked` | Time slot reserved during pending window |
| `arrival_auto_detected` | System detected provider coordinates match customer |
| `job_auto_completed` | Provider did not respond in 1 hour — auto-marked done |
| `cancellation_risk_updated` | Provider score updated after cancellation |
| `rating_score_recalculated` | Full score recalculation after customer rating |

---

## 5. Agent Pipeline

The orchestration pipeline runs in this order for every request.

```
Customer describes problem
          │
          ▼
┌─────────────────────┐
│  1. IntentParser    │  Gemini 3.1 Pro — extracts all intent fields
└────────┬────────────┘
         │ confidence < 0.7 → clarification question returned
         ▼
┌─────────────────────┐
│  2. ProviderMatcher │  Gemini for ranking rationale + top 3 selection
└────────┬────────────┘
         │ 0 results → radius expand → retry
         │ customer asks for more → return next batch
         ▼
┌─────────────────────┐
│  3. BookingSimulator│  Deterministic — creates job record, locks slot
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│  4. NotificationSvc │  Push to provider (job details)
└────────┬────────────┘
         │
         ├── Provider accepts
         │         ▼
         │   ┌─────────────────────┐
         │   │  5. LocationTracker │  Simulates provider travel
         │   └────────┬────────────┘
         │            │ coordinates match → ArrivalDetector
         │            ▼
         │   ┌─────────────────────┐
         │   │  6. JobMonitor      │  Sends completion reminder to provider
         │   └────────┬────────────┘
         │            │ marked done (or auto after 1hr)
         │            ▼
         │   ┌─────────────────────┐
         │   │  7. ScoreUpdater    │  Recalculates provider 8-factor scores
         │   └────────┬────────────┘
         │            ▼
         │   ┌─────────────────────┐
         │   │  8. RatingRequest   │  Sends star form to customer
         │   └─────────────────────┘
         │
         └── Provider cancels
                   ▼
           ┌─────────────────┐
           │ CancellationSvc │  Updates cancellation_risk, restarts search
           └─────────────────┘
                   │
                   └── Go back to ProviderMatcher (step 2)
```

---

## 6. Provider Dataset Schema

**File:** `backend/data/mock_providers.json`
**Count:** 20 providers across Islamabad and Lahore

### Full Provider Object

```json
{
  "id": "p001",
  "name": "Ali",
  "shop_name": "Ali AC Services",
  "job_role": "AC Technician",
  "service_expertise": ["ac_repair", "ac_installation", "ac_maintenance", "ac_gas_refill"],
  "location": {
    "latitude": 33.6844,
    "longitude": 73.0479,
    "city": "Islamabad",
    "area": "G-13"
  },
  "availability_status": true,
  "charges_per_hour": 800,
  "travel_charges_per_km": 20,
  "rating": 4.7,
  "on_time_score": 0.94,
  "cancellation_risk": 0.04,
  "capacity": 2,
  "jobs_completed": 142,
  "review_sentiment_score": 0.88,
  "skill_level": "intermediate",
  "certifications": ["AC Technician Level 2"],
  "review_recency_days": 3,
  "expertise_problems": [
    {
      "problem_type": "ac_not_cooling",
      "estimated_hours_min": 1.0,
      "estimated_hours_max": 2.5
    },
    {
      "problem_type": "ac_gas_refill",
      "estimated_hours_min": 0.5,
      "estimated_hours_max": 1.0
    },
    {
      "problem_type": "ac_installation",
      "estimated_hours_min": 2.0,
      "estimated_hours_max": 4.0
    }
  ]
}
```

### Provider Field Reference

| Field | Type | Description |
|---|---|---|
| `id` | string | Unique provider identifier (p001–p020) |
| `name` | string | Provider's personal name |
| `shop_name` | string | Business name (optional) |
| `job_role` | string | Primary job title e.g. "AC Technician" |
| `service_expertise` | string[] | All service types this provider handles |
| `location.latitude` | float | Current GPS latitude |
| `location.longitude` | float | Current GPS longitude |
| `location.city` | string | City of operation |
| `location.area` | string | Neighbourhood/sector |
| `availability_status` | boolean | Online (true) = eligible for matching |
| `charges_per_hour` | int | Standard hourly rate in PKR |
| `travel_charges_per_km` | int | Travel cost per km (default Rs. 20/km) |
| `rating` | float | Weighted average of all customer star ratings |
| `on_time_score` | float | Ratio of on-time arrivals 0.0–1.0 |
| `cancellation_risk` | float | Ratio of accepted-then-cancelled jobs 0.0–1.0 |
| `capacity` | int | Current simultaneous jobs the provider can handle |
| `jobs_completed` | int | Total lifetime jobs completed |
| `review_sentiment_score` | float | Gemini-analysed sentiment of reviews 0.0–1.0 |
| `skill_level` | string | basic / intermediate / complex |
| `certifications` | string[] | Formal qualifications |
| `review_recency_days` | int | Days since most recent review |
| `expertise_problems` | array | Problem-specific time estimates |

### Score Recalculation After Job Completion

After every completed job with a customer rating:

```
new_rating = weighted_average(all_ratings)
  where recent ratings weighted 1.5× vs ratings older than 30 days

on_time_score = on_time_arrivals / total_accepted_jobs

cancellation_risk = cancelled_after_accept / total_accepted_jobs

review_sentiment_score = Gemini sentiment analysis on latest 10 reviews
  returns float 0.0 (very negative) to 1.0 (very positive)

capacity = max_capacity - current_active_jobs
```

---

## 7. Customer Dataset Schema

**File:** `backend/data/sessions.json` (runtime) + booking records

```json
{
  "customer_id": "cust_001",
  "name": "Ahmed Khan",
  "city": "Islamabad",
  "location": {
    "latitude": 33.6801,
    "longitude": 73.0512
  }
}
```

### Customer Field Reference

| Field | Type | Description |
|---|---|---|
| `customer_id` | string | Unique customer identifier |
| `name` | string | Customer's full name |
| `city` | string | Customer's city |
| `location.latitude` | float | Customer GPS latitude (for distance calculation) |
| `location.longitude` | float | Customer GPS longitude (for distance calculation) |

Customer location is used by the ProviderMatcher to calculate:
- Travel distance from provider to customer (Haversine formula)
- Travel cost (distance × provider's `travel_charges_per_km`)
- Estimated travel time (distance / assumed avg speed of 30 km/h in city)

---

## 8. Job Schema

**File:** `backend/data/mock_bookings.json`

```json
{
  "booking_id": "BK-20250516-0001",
  "customer_name": "Ahmed Khan",
  "customer_location": {
    "latitude": 33.6801,
    "longitude": 73.0512
  },
  "service_provider_name": "Ali",
  "service_provider_shop": "Ali AC Services",
  "service_provider_id": "p001",
  "service_type": "ac_repair",
  "problem_description": "AC bilkul thanda nahi kar raha, shayad gas khatam ho gayi hai",
  "time_to_arrive": "2025-05-17T10:00:00.000Z",
  "estimated_time_to_complete_hours": 2.0,
  "charges": {
    "service_charges": 1600,
    "travel_charges": 120,
    "on_demand_charges": 200,
    "total_charges": 1920
  },
  "status": "accepted",
  "status_history": [
    { "status": "pending_provider", "timestamp": "2025-05-16T10:00:00.000Z" },
    { "status": "accepted",         "timestamp": "2025-05-16T10:04:22.000Z" }
  ],
  "created_at": "2025-05-16T10:00:00.000Z",
  "updated_at": "2025-05-16T10:04:22.000Z",
  "customer_rating": null,
  "completion_marked_at": null,
  "auto_completed": false
}
```

### Charges Breakdown

| Charge field | Formula |
|---|---|
| `service_charges` | `charges_per_hour × estimated_hours_max` |
| `travel_charges` | `haversine_distance_km × travel_charges_per_km` |
| `on_demand_charges` | Urgency surcharge: high→Rs.200, medium→Rs.100, low→Rs.0 |
| `total_charges` | `service_charges + travel_charges + on_demand_charges` |

All charges rounded to nearest Rs. 10. No decimals.

---

## 9. Matching Algorithm — 8 Factors

The ProviderMatcher scores every eligible provider against 8 weighted
factors. Composite score ranges from 0.0 to 1.0.

```
Composite Score =
  (0.20 × Travel Time Score)        ← proximity to customer
+ (0.15 × Availability Score)       ← online status + capacity
+ (0.15 × Specialisation Score)     ← service expertise match
+ (0.15 × On-Time Score)            ← historical reliability
+ (0.15 × Review Sentiment Score)   ← Gemini-analysed review quality
+ (0.10 × Rate Score)               ← price competitiveness
+ (0.05 × Cancellation Risk Score)  ← inverse of cancellation rate
+ (0.05 × Capacity Score)           ← available slots right now
```

### Factor 1 — Travel Time (20%)

```
distance_km = haversine(customer_lat, customer_lng,
                        provider_lat, provider_lng)

estimated_travel_mins = (distance_km / 30) × 60
  ← assumes 30 km/h average city speed

travel_time_score = max(0, 1 − distance_km / 25)
  ← score decays to 0 at 25 km
```

This is the highest-weighted factor because travel time directly
affects the customer's waiting experience and the provider's fuel
cost. Providers within 3 km score above 0.88.

### Factor 2 — Availability (15%)

```
if provider.availability_status == false:
  availability_score = 0.0   ← offline providers excluded entirely

if provider.capacity == 0:
  availability_score = 0.0   ← at maximum capacity, excluded

availability_score = min(1.0, provider.capacity / 3)
  ← normalised by assumed max of 3 simultaneous jobs
```

Offline providers and providers at capacity are excluded via hard
filter before scoring, so this factor acts as a capacity quality
signal for available providers.

### Factor 3 — Service Specialisation (15%)

```
exact_match = problem_type in provider.expertise_problems
category_match = service_type in provider.service_expertise

if exact_match:
  specialisation_score = 1.0
elif category_match:
  specialisation_score = 0.7
else:
  specialisation_score = 0.0   ← excluded by hard filter
```

Providers who have the specific `problem_type` (e.g. `ac_not_cooling`)
in their `expertise_problems` array score higher than providers who
only broadly offer `ac_repair`. This rewards specialisation.

### Factor 4 — On-Time Score (15%)

```
on_time_score = provider.on_time_score   ← already 0.0–1.0
```

Direct use of the provider's historical on-time arrival ratio.
A provider at 94% on-time scores 0.94. Updated after every job.

### Factor 5 — Review Sentiment (15%)

```
review_sentiment_score = provider.review_sentiment_score
  ← Gemini-analysed sentiment of the provider's latest reviews
  ← ranges 0.0 (very negative) to 1.0 (very positive)
  ← recalculated after each new customer rating
```

This goes beyond star ratings. Gemini reads the text of the most
recent reviews and extracts sentiment signals: "kaam acha kiya",
"time par aaya", "mehenga tha", "dobara nahi bulaonga". These nuances
are not captured by star ratings alone.

### Factor 6 — Rate Score (10%)

```
market_avg = 800  ← PKR baseline for Islamabad

rate_score = 1 − abs(provider.charges_per_hour − market_avg)
             / market_avg / 2
  ← providers near market average score highest
  ← both very cheap and very expensive score lower
```

### Factor 7 — Cancellation Risk (5%)

```
cancellation_risk_score = 1 − provider.cancellation_risk
  ← inverse: lower cancellation rate → higher score

if provider.cancellation_risk > 0.30:
  provider is EXCLUDED from matching entirely (hard filter)
```

### Factor 8 — Capacity (5%)

```
capacity_score = provider.capacity / max_capacity
  ← where max_capacity = 3 (assumed)
  ← provider with 2 current jobs scores 0.33
  ← provider with 0 current jobs scores 1.0
```

### Hard Exclusion Filters (applied before scoring)

Providers are removed from the candidate pool entirely if:
- `availability_status == false`
- `capacity == 0`
- `cancellation_risk > 0.30`
- `service_type` not in `service_expertise`

### Ranking Example Output

```
Provider            Travel  Avail  Special  OnTime  Sentiment  Rate  Cancel  Cap  SCORE
────────────────────────────────────────────────────────────────────────────────────────
Ali AC Services     0.95   1.0    1.0      0.94    0.88       0.80  0.96    1.0  0.938
Khalid AC Expert    0.88   1.0    1.0      0.84    0.76       0.85  0.90    0.7  0.876
Tariq AC & Cooling  0.91   1.0    0.7      0.78    0.65       0.95  0.89    1.0  0.831
```

Top 3 are returned to the customer. Customer selects or asks for more.

---

## 10. Job Status State Machine

```
             Customer selects provider
                       │
                       ▼
             ┌─────────────────────┐
             │  pending_provider   │ ← Awaiting provider response
             └────────┬────────────┘
                      │
            ┌─────────┴──────────┐
            │                    │
     Provider accepts      Provider cancels
            │                    │
            ▼                    ▼
    ┌────────────┐      ┌──────────────────┐
    │  accepted  │      │  cancelled       │
    └─────┬──────┘      │  (search restart)│
          │             └──────────────────┘
          │ (1 hour before arrival time)
          ▼
    ┌────────────┐
    │  arriving  │ ← Push notification to customer
    └─────┬──────┘
          │ (GPS coordinates match — auto-detected)
          ▼
    ┌────────────┐
    │  arrived   │ ← System auto-detected via location
    └─────┬──────┘
          │ (provider starts work)
          ▼
    ┌─────────────┐
    │ in_progress │
    └──────┬──────┘
           │ (provider marks done OR 1hr auto-complete)
           ▼
    ┌───────────┐
    │ completed │ ← Scores recalculated, rating form sent
    └───────────┘
```

### Status Definitions

| Status | Trigger | Action |
|---|---|---|
| `pending_provider` | Customer selects provider | Push notification to provider |
| `accepted` | Provider taps Accept | Push notification to customer |
| `arriving` | 1 hour before `time_to_arrive` | Push notification to customer |
| `arrived` | GPS match auto-detected | Status auto-updated, customer notified |
| `in_progress` | After arrived (can be manual) | No notification |
| `completed` | Provider marks done OR auto after 1 hr | Scores updated, rating form sent |
| `cancelled` | Provider cancels | Cancellation risk updated, search restarts |

### Location-Based Arrival Detection

Provider location is simulated by interpolating their coordinates
toward the customer's coordinates over time. The system checks
every 60 seconds:

```
distance = haversine(provider.lat, provider.lng,
                     customer.lat, customer.lng)

if distance < 0.15:   ← within 150 metres
  update_status(booking_id, "arrived")
  send_push_notification(customer, "Provider has arrived!")
```

---

## 11. Push Notification Events

### To Service Provider

| Event | Trigger | Message |
|---|---|---|
| New job | Customer selects this provider | "Naya kaam aaya! [Service] in [Area]. Rs. [Amount]. Tap to view details." |
| Job completion reminder | After estimated completion time | "Kya aap ne [Service] ka kaam mukammal kar diya? Mark as done karein." |

### To Customer

| Event | Trigger | Message |
|---|---|---|
| Provider accepted | Provider taps Accept | "[Provider Name] ne kaam accept kar liya! Woh aap ke paas [Time] ko pohunchein ge." |
| Provider cancelled | Provider cancels | "[Provider Name] ne cancel kar diya. Hum aap ke liye doosra provider dhundh rahe hain." |
| Provider on the way | Status changes to Arriving | "[Provider Name] rawan ho gaye hain. Takriban [Time] mein pohunchein ge." |
| Job completed | Status changes to Completed | "Kaam mukammal ho gaya! Kripaya [Provider Name] ko rating dein." |

---

## 12. APIs and Tools

### Backend REST API

**Base URL:** `http://localhost:3000`

#### Session & Orchestration

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/health` | Health check — service status and version |
| `POST` | `/api/session/create` | Create new customer session |
| `GET` | `/api/session/:id` | Get full session state |
| `PATCH` | `/api/session/:id` | Update any session field |
| `POST` | `/api/orchestrate` | Run full agent pipeline from user input |

#### Provider Matching

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/providers` | List all providers |
| `POST` | `/api/providers/match` | Match providers to intent |
| `GET` | `/api/providers/:id` | Get single provider details |
| `PATCH` | `/api/providers/:id/scores` | Update provider scores after job |

#### Booking Management

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/booking/create` | Create booking after customer selection |
| `GET` | `/api/booking/:id` | Get full booking record |
| `PATCH` | `/api/booking/:id/status` | Update job status |
| `POST` | `/api/booking/:id/cancel` | Provider cancels — triggers restart |
| `POST` | `/api/booking/:id/complete` | Mark job as done |
| `POST` | `/api/booking/:id/rating` | Submit customer star rating |

#### Location & Tracking

| Method | Endpoint | Description |
|---|---|---|
| `PATCH` | `/api/provider/:id/location` | Update provider GPS coordinates |
| `GET` | `/api/booking/:id/distance` | Get current provider-to-customer distance |
| `POST` | `/api/booking/:id/check-arrival` | Check if provider has arrived |

#### Notifications & Trace

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/notify/provider` | Send push notification to provider |
| `POST` | `/api/notify/customer` | Send push notification to customer |
| `GET` | `/api/trace/export/:session_id` | Export full agent trace JSON |

### External Tools and Services

| Tool | Purpose | Free? |
|---|---|---|
| `@google/genai` | Gemini API — intent parsing, ranking rationale, sentiment | Free tier via AI Studio |
| Google Antigravity | Agent orchestration IDE and plan execution | Hackathon access |
| Flutter `local_notifications` | Push notifications on mobile | Free |
| Haversine formula | Distance calculation between GPS coordinates | Custom — no Maps API needed |
| `dotenv` | Environment variable management | Free |

### Environment Variables

```env
PORT=3000
GEMINI_API_KEY=AIzaSy...    # Get free from aistudio.google.com
```

No Anthropic API. No OpenAI. No Google Maps API. No paid services.

---

## 13. Assumptions

**Location**
- Provider and customer locations are stored as GPS coordinates
  (latitude + longitude). For the demo, these are seeded in mock data.
- Travel speed is assumed at 30 km/h average (typical Islamabad/Lahore
  city traffic). No real traffic data API is used.
- Arrival is detected when provider coordinates are within 150 metres
  of customer coordinates.

**Providers**
- 20 mock providers cover Islamabad (G-sector, F-sector, I-sector, DHA)
  and Lahore (DHA, Gulberg, Johar Town) service areas.
- Provider location is simulated by interpolating coordinates toward
  customer over time — no real GPS hardware is involved.
- A provider can handle a maximum of 3 simultaneous jobs (capacity = 3).

**Pricing**
- All prices are in Pakistani Rupees (PKR).
- All prices are rounded to the nearest Rs. 10. No decimals.
- Service charges cover labour only. Parts and equipment are excluded
  and must be agreed between customer and provider on-site.
- Travel charges are calculated as `distance_km × provider.travel_charges_per_km`.
- On-demand/urgency charge: high urgency = Rs. 200, medium = Rs. 100, low = Rs. 0.

**Notifications**
- Push notifications are simulated using the Flutter `local_notifications`
  package. In production, this would be replaced with Firebase Cloud
  Messaging (FCM) for real device delivery.
- The 1-hour provider completion reminder is triggered by a server-side
  timer set at booking creation, based on `estimated_time_to_complete_hours`.
- Auto-complete fires if the provider does not respond within 60 minutes
  of the completion reminder.

**Language**
- Roman Urdu keyword mapping covers the 80+ most common service-request
  terms used in Lahore and Islamabad WhatsApp conversations, collected
  from real informal economy communications.
- Gemini handles all ambiguous, mixed-language, and misspelled inputs.
- If Gemini confidence is below 0.7, a single clarifying question is
  asked before matching proceeds.

**Data**
- No external database is used. All data is stored as JSON flat files
  in `/backend/data/`. In production, this would be replaced with
  PostgreSQL and proper indexing.
- Sessions expire after 30 minutes of inactivity.

---

## 14. Cost and Latency Analysis

### Gemini API Calls Per Session

| Step | Gemini call? | Avg tokens | Avg latency |
|---|---|---|---|
| IntentParser | Yes | ~800 in / ~300 out | 1,200 ms |
| ProviderMatcher (rationale) | Yes | ~600 in / ~150 out | 900 ms |
| Review sentiment analysis | Yes (per provider update) | ~400 in / ~50 out | 700 ms |
| Total per booking session | 2 calls | ~1,400 in / ~450 out | ~2,100 ms |

### Cost Estimate (Gemini 3.1 Pro pricing — free tier for hackathon)

- Free tier: 50 requests/day per project
- All demo sessions run within free tier limits
- Production estimate at 1,000 bookings/day: ~2,000 Gemini calls/day
  at approximately $0.0025 per 1K input tokens → ~$3.50/day at scale

### End-to-End Latency

| Phase | Time |
|---|---|
| Intent parsing (Gemini) | 1,200 ms |
| Provider matching (scoring) | < 50 ms |
| Matching rationale (Gemini) | 900 ms |
| Booking creation | < 20 ms |
| Push notification | < 100 ms |
| **Total from user input to booking confirmation** | **~2,300 ms** |

The 2.3-second response time from customer input to booking confirmation
is acceptable for a conversational interface. The Gemini calls are the
primary bottleneck. In production, the ranking rationale call could be
made asynchronous (show providers immediately, load rationale after)
to reduce perceived latency to under 1.5 seconds.

---

## 15. Baseline Comparison

### Hazir vs Current Reality (WhatsApp/Phone)

| Capability | Current method | Hazir |
|---|---|---|
| Finding a provider | Manual calls, asking contacts | Automated in < 3 seconds |
| Price transparency | No reference point — fully ad-hoc | Calculated from provider rates + industry standards |
| Provider trust signals | Word of mouth only | Rating, on-time score, sentiment, cancellation risk |
| Scheduling | Verbal, often forgotten | Confirmed booking with reminders |
| Tracking provider | Call and ask "kahan ho?" | GPS-based automatic arrival detection |
| Dispute resolution | No mechanism | Logged, cancellation risk updated |
| Rating and feedback | None | Star rating collected after every job |
| Language support | Works in any language | AI handles Urdu, Roman Urdu, English, mixed |

### Hazir vs Existing Pakistani Apps

| Capability | Rozee/OLX | TaskNow | Hazir |
|---|---|---|---|
| Informal sector focus | Partial | Yes | Yes |
| Multilingual AI (Roman Urdu) | No | No | Yes |
| Real-time provider matching | No | Basic | 8-factor scored |
| Conversational interface | No | No | Yes — full chat |
| Live location tracking | No | No | Yes — simulated GPS |
| Agentic reasoning trace | No | No | Yes — full Antigravity log |
| Automated reminders | No | Partial | Yes — push notifications |
| Review sentiment analysis | No | No | Yes — Gemini NLP |

---

## 16. Privacy Note

**Data collected**
- Customer: name, city, GPS coordinates (latitude/longitude)
- Provider: name, shop name, GPS coordinates, job role, service expertise
- Job records: booking ID, service type, problem description, charges

**Data not collected**
- No phone numbers stored in the system
- No payment card or banking information
- No personal identification documents
- No photos or video from any party

**Data storage**
- All data is stored locally in JSON flat files in `/backend/data/`
  on the server running the demo. No data is transmitted to any
  third party other than Google Gemini for AI inference.

**Gemini data usage**
- Text sent to Gemini for intent parsing and sentiment analysis
  contains only the service request description and provider reviews.
  No personally identifiable information (name, phone number, address)
  is included in any Gemini prompt.

**Location data**
- GPS coordinates are used only for distance calculation and arrival
  detection. They are stored in the session and booking record.
- For the demo, all coordinates are mock/simulated. No real GPS
  tracking of real people occurs.

**Retention**
- Session data expires after 30 minutes of inactivity.
- Booking records are retained for the duration of the demo.
- Agent trace logs are retained for submission to judges only.

**Production note**
A production version of Hazir would require a formal privacy policy,
consent flows for location access, PDPA (Pakistan's data protection
framework) compliance review, and Firebase Authentication for proper
user identity management.

---

## 17. Limitations

**No real GPS hardware**
Provider location is simulated by interpolating coordinates toward
the customer. In production, real GPS tracking via Flutter's
`geolocator` package would be required with the provider's consent.

**No real push notifications**
Notifications use Flutter's `local_notifications` package which
triggers on the same device. In production, Firebase Cloud Messaging
(FCM) would deliver notifications to remote devices.

**No payment processing**
The system calculates and displays charges but does not process any
payments. All financial transactions would need to be handled by a
Pakistani payment gateway (JazzCash, EasyPaisa) in production.

**Mock data only**
20 providers and all their ratings, scores, and job histories are
seeded mock data. Real data would require an onboarding flow for
providers and a track record built from real completed jobs.

**Single server, no scaling**
The Express backend runs as a single process with JSON flat files.
No load balancing, no database, no horizontal scaling. Production
would require PostgreSQL, Redis for session management, and a
containerised deployment (Docker/Kubernetes).

**No SMS fallback**
Providers in Pakistan often have low-end phones. A production system
would need SMS fallback for push notification delivery failures.

**Review sentiment only updated on new ratings**
Gemini sentiment analysis runs only when a new customer rating is
submitted. In production, this would run continuously as new review
text accumulates.

**Language model hallucination risk**
Gemini may occasionally misparse strongly ambiguous inputs. The
confidence score and clarification question system mitigates this
but cannot eliminate it entirely. Low-confidence responses are
always surfaced to the user for confirmation before matching proceeds.

**No real cancellation enforcement**
Cancellation risk is tracked and updated in the provider's score,
which affects future matching rankings. There is no financial
penalty, deposit, or blocking mechanism in the demo. Production
would require a graduated penalty system.

---

## 18. How to Run

### Prerequisites

- Node.js v18 or above
- Flutter SDK 3.x
- A free Google Gemini API key from [aistudio.google.com](https://aistudio.google.com)

### Backend

```bash
# Clone the repo
git clone https://github.com/munirhassan-ux/ai-service-orchestrator.git
cd ai-service-orchestrator/backend

# Install dependencies
npm install

# Create environment file
cp .env.example .env
# Add your Gemini key: GEMINI_API_KEY=AIzaSy...

# Start development server
npm run dev

# Server starts at http://localhost:3000
# Health check: GET http://localhost:3000/health
```

### Frontend

```bash
cd ../frontend

# Install Flutter dependencies
flutter pub get

# Run on connected device or simulator
flutter run

# For web (demo mode)
flutter run -d chrome
```

### Verify the Connection

Open the app. You should see the Hazir role selection screen. Tap
"Mujhe service chahiye" and type:

```
AC kaam nahi kar raha, kal subah G-13 mein chahiye
```

The AI should respond with a typing indicator followed by 3 matched
providers within 3 seconds.

### Demo Scenarios

**Scenario 1 — Happy path (Roman Urdu, AC repair)**
```
Input: "AC bilkul kaam nahi, kal subah G-13"
Expected: ac_repair → 3 providers ranked → customer selects →
          booking confirmed → provider notified
```

**Scenario 2 — Provider cancels, search restarts**
```
Input: Any service booking
Action: Provider taps Cancel in provider chat
Expected: Customer notified → cancellation_risk updated →
          3 new providers shown
```

**Scenario 3 — English input, plumber**
```
Input: "I need a plumber for pipe leakage in F-10 today evening"
Expected: plumber → pipe_leakage problem type → 3 matches →
          charges calculated with travel cost
```

---

## Submission Artifacts

| Artifact | Location |
|---|---|
| Working prototype | Flutter app + Express backend (this repo) |
| Demo video (3–5 min) | `demo/hazir_demo.mp4` |
| Agent trace logs | `backend/data/agent_traces/` |
| Antigravity workplan | `docs/antigravity_workplan.md` |
| README (this file) | `README.md` |

---

## Team

Built for the Google Antigravity Hackathon — Challenge 2: AI Service
Orchestrator for Informal Economy.

App: **Hazir** — حاضر — "Present. Ready. Here for you."

---

*Hazir uses Google Gemini 3.1 Pro via Antigravity for all AI
reasoning. No other LLM is used. All prices in PKR.*
