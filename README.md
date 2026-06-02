# Hazir — AI Service Orchestrator for Pakistan's Informal Economy

> **Google Antigravity Hackathon — Challenge 2**
> App Name: **Hazir** (حاضر — meaning "Present" / "Ready")
> Repo: [github.com/munirhassan-ux/ai-service-orchestrator](https://github.com/munirhassan-ux/ai-service-orchestrator)
> Stack: Flutter (Dart) · TypeScript/Node.js · Google Gemini via Antigravity

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
19. [Recent Improvements](#19-recent-improvements)

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
- Finds and ranks the 3 best available providers using 8 factors and **real geocoded coordinates**
- Confirms the booking and notifies the provider via push notification
- Tracks the provider's simulated location on a **live OpenStreetMap** in real time
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
│  │  Live Map Track  │                ┌──────────▼────────────┐ │
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
│                               │   Google Gemini Pro          │ │
│                               │   via @google/genai SDK      │ │
│                               │   Orchestrated by            │ │
│                               │   Google Antigravity         │ │
│                               └──────────────────────────────┘ │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  JSON Data Layer  /backend/data/                         │  │
│  │  mock_providers.json     — 50,960 providers (all Pakistan│  │
│  │  mock_bookings.json      — job records and status        │  │
│  │  mock_schedule.json      — slot reservation registry     │  │
│  │  roman_urdu_map.json     — language signal mapping       │  │
│  │  sessions.json           — active customer sessions      │  │
│  │  sub_tehsils_pakistan.csv— 728 geocoded sub-tehsil locs  │  │
│  │  agent_traces/           — per-session Antigravity logs  │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Technology Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart) — `/frontend/` |
| Backend | TypeScript, Express.js, Node.js — `/backend/` |
| AI Model | Google Gemini Pro |
| AI SDK | `@google/genai` npm package |
| Orchestration | Google Antigravity |
| Geocoding | Nominatim (OpenStreetMap) — free, no API key |
| Map Rendering | `flutter_map` + OpenStreetMap tiles |
| Push Notifications | Flutter `local_notifications` package |
| Location Simulation | Haversine-based coordinate interpolation |
| Data Store | JSON flat files (no external database for demo) |

---

## 3. User Flow

### Customer Flow

```
1. Open app
   └── Home screen checks for active bookings (API) and open sessions (in-memory)
       ├── Active session exists → "Resume Chat" shown, new prompt disabled
       └── No active session → prompt input enabled

2. Customer types their service request
   ├── Session created immediately, tracked in ActiveSessionService
   ├── If user navigates back mid-load → orchestration continues in background
   │   └── Result saved to ActiveSessionService → home shows "Resume Chat"
   └── Prompt sent to AI orchestrator

3. AI presents 3 best matches (with real geocoded distance)
   Ranked by: travel time, availability, service specialisation,
   on-time score, review sentiment, rate, cancellation risk, capacity
   └── Customer reads each provider card — Select Provider / More Options
       (buttons disabled after tap to prevent double-selection)

4a. Customer selects a provider
    └── Chat input hidden — no further prompting allowed
    └── Booking confirmed, session linked to booking ID
    └── Home screen shows "Active Booking" banner

4b. Customer asks for more options
    └── Previous providers excluded, next batch loaded

5. Live GPS tracking (ACCEPTED / ARRIVING status)
   └── OpenStreetMap map rendered with:
       ├── Customer location: geocoded from prompt location string (Nominatim)
       ├── Provider location: actual provider coordinates from dataset
       ├── Starting distance: provider.distance_km × 1000 (matches card shown)
       └── Green bike icon animates toward customer house pin every 1 second

6. Provider arrives (ARRIVED status)
   └── Map replaced by job checklist

7a. Job completed
    └── Star rating form sent in chat
    └── ActiveSessionService cleared → home re-enables new booking prompt

7b. Provider cancels
    └── Booking stays on Active tab (not History)
    └── Two options shown in chat:
        ├── "Find New Provider" — restores full conversation history, creates
        │   new session with cancelled provider excluded, skips intake phase,
        │   goes directly to matching new providers
        └── "Cancel and End Chat" — sets status CANCELLED_CUSTOMER,
            clears session, booking moves to History tab
```

### Service Provider Flow

```
1. Open provider view (toggle in top-right)
   └── Jobs tab shows active and history bookings

2. Tap a job → Provider Chat Screen
   └── Chat input hidden throughout — interaction via buttons only
   └── Checklist hidden until status = ARRIVED (not shown on ACCEPTED/ARRIVING)

3a. Provider accepts (PENDING_PROVIDER status)
    └── Accept / Decline buttons active
    └── After tapping, buttons become permanently disabled (grey)
    └── Job status → ACCEPTED

3b. Provider declines
    └── Customer notified, cancellation risk updated

4. Provider travels to customer
   └── GPS simulation: distance decreases every 1 second
   └── Status: ARRIVING → ARRIVED
   └── On ARRIVED: checklist automatically appears in provider chat

5. Provider completes job checklist
   └── Each checklist item tap calls API (mark complete)
   └── "Mark Job as Complete" enabled only when all items ticked

6. Job completed
   └── ActiveSessionService cleared on customer side
   └── Home screen re-enables new booking for customer
```

---

## 4. Antigravity Workflow

Antigravity is the core orchestration platform for Hazir. It controls the
entire reasoning and execution pipeline for every agent call in the system.

### How Antigravity is Used

**Agent Orchestration**
Antigravity manages the sequential execution of all agents in the
pipeline: IntentParser → ProviderMatcher → BookingSimulator →
LocationTracker → ScoreUpdater. Each agent is a structured reasoning
step within Antigravity's planning framework.

**Gemini Model Access**
Every agent that requires language understanding or decision-making
calls Google Gemini Pro through the `@google/genai` SDK managed by
Antigravity. This includes: multilingual intent extraction, provider
ranking rationale generation, and conversational response generation.
No other LLM is used anywhere in the system.

**Plan Mode — Workplan Generation**
Antigravity's Plan mode was used at the start of each development
session to generate a structured workplan and task execution order
before code was written. These workplans form part of the submission
artifacts alongside the agent trace logs.

**Trace Log Generation**
Every orchestration session produces a structured JSON trace file at
`/backend/data/agent_traces/[session_id].json`. This is the primary
submission artifact for the hackathon. It captures every agent step,
every Gemini call, every decision and fallback, and the final outcome.

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
      "model": "gemini-pro",
      "prompt_summary": "Extract intent from: 'AC kaam nahi kar raha, kal subah G-13'",
      "gemini_decision": "ac_repair, G-13, tomorrow morning, urgency: high, roman_urdu",
      "confidence": 0.94,
      "output": {
        "service_type": "ac_repair",
        "location": "G-13",
        "preferred_time": "tomorrow_morning",
        "language": "roman_urdu",
        "confidence": 0.94,
        "clarification_needed": false
      },
      "duration_ms": 1240
    },
    {
      "step": 2,
      "agent": "Geocoder",
      "model": null,
      "gemini_decision": "Nominatim API call — deterministic",
      "output": {
        "location": "G-13, Islamabad",
        "resolved_lat": 33.6844,
        "resolved_lng": 73.0479,
        "source": "nominatim_api"
      },
      "duration_ms": 180
    },
    {
      "step": 3,
      "agent": "ProviderMatcher",
      "model": "gemini-pro",
      "gemini_decision": "Top 3 selected using geocoded customer coords. Ali AC Services ranked first: 1.2km real distance.",
      "output": {
        "providers_returned": 3,
        "top_provider": "Ali AC Services",
        "distance_km": 1.2,
        "composite_score": 0.81
      },
      "duration_ms": 2340
    },
    {
      "step": 4,
      "agent": "BookingSimulator",
      "model": null,
      "gemini_decision": "Deterministic — no model call",
      "output": {
        "booking_id": "BK-20250516-0001",
        "status": "pending_provider",
        "distance_meters": 1200,
        "customer_lat": 33.6844,
        "customer_lng": 73.0479
      },
      "duration_ms": 18
    }
  ],
  "final_outcome": "booked"
}
```

---

## 5. Agent Pipeline

```
Customer describes problem
          │
          ▼
┌─────────────────────┐
│  1. IntentParser    │  Gemini Pro — extracts all intent fields
└────────┬────────────┘
         │ confidence < 0.75 → clarification question returned
         ▼
┌─────────────────────┐
│  2. Geocoder        │  Nominatim API → real lat/lng for location string
└────────┬────────────┘  (cached in memory — called once per unique location)
         ▼
┌─────────────────────┐
│  3. ProviderMatcher │  Haversine from geocoded coords → 8-factor scoring
└────────┬────────────┘
         │ 0 results → radius expand → retry
         │ customer asks for more → return next batch (providers_tried excluded)
         ▼
┌─────────────────────┐
│  4. BookingSimulator│  Async — uses geocoded customer coords
└────────┬────────────┘  distance_meters = provider.distance_km × 1000
         │
         ▼
┌─────────────────────┐
│  5. NotificationSvc │  Push to provider (job details)
└────────┬────────────┘
         │
         ├── Provider accepts
         │         ▼
         │   ┌─────────────────────┐
         │   │  6. LocationTracker │  Simulates provider travel (1s intervals)
         │   └────────┬────────────┘  distance_meters decreases toward 0
         │            │ coordinates match → ArrivalDetector
         │            ▼
         │   ┌─────────────────────┐
         │   │  7. ChecklistUnlock │  Checklist shown to provider on ARRIVED
         │   └────────┬────────────┘
         │            │ all items ticked
         │            ▼
         │   ┌─────────────────────┐
         │   │  8. ScoreUpdater    │  Recalculates provider scores
         │   └────────┬────────────┘
         │            ▼
         │   ┌─────────────────────┐
         │   │  9. RatingRequest   │  Star form sent to customer in chat
         │   └─────────────────────┘
         │
         └── Provider cancels
                   ▼
           ┌──────────────────┐
           │ CancellationSvc  │  Updates cancellation_risk
           └────────┬─────────┘
                    │  Customer sees two options:
                    ├── "Find New Provider" → session pre-loaded with
                    │   parsed_intent + providers_tried (excludes cancelled)
                    │   → directly enters matching phase, skips intake
                    └── "Cancel and End Chat" → status = CANCELLED_CUSTOMER
                        → booking moves to History
```

---

## 6. Provider Dataset Schema

**File:** `backend/data/mock_providers.json`
**Count:** 50,960 providers across all of Pakistan
**Generation:** `backend/data/generate_providers.py` using `sub_tehsils_pakistan.csv`

The dataset was generated programmatically from 728 Pakistani sub-tehsil
locations (with real latitude/longitude from the Election Commission of
Pakistan dataset). Each sub-tehsil has providers across 10 service types,
7 providers per service type per location, with randomised but realistic
attributes (rating, on-time score, base rate, cancellation risk).

### Provider Object

```json
{
  "provider_id": "p00001",
  "name": "Yasir Abbasi",
  "shop_name": "Yasir Abbasi AC Technician Services",
  "location": {
    "latitude": 30.052416,
    "longitude": 73.297449
  },
  "city": "Bahawalnagar",
  "city_area": "Bahawalnagar",
  "availability_status": "online",
  "charges": {
    "base_rate": 604,
    "travel_rate": 41
  },
  "job_role": "AC Technician",
  "service_expertise": ["ac_installation", "ac_maintenance"],
  "rating": 4.4,
  "on_time_score": 0.83,
  "cancellation_risk": 0.07,
  "capacity": 2,
  "active_jobs": 0,
  "total_reviews": 116,
  "total_jobs": 175
}
```

### Provider Field Reference

| Field | Type | Description |
|---|---|---|
| `provider_id` | string | Unique identifier (p00001–p50960) |
| `name` | string | Provider's personal name |
| `shop_name` | string | Business name |
| `job_role` | string | Primary job title |
| `service_expertise` | string[] | Service types offered |
| `location.latitude` | float | GPS latitude (real sub-tehsil location ± jitter) |
| `location.longitude` | float | GPS longitude |
| `city` | string | District name from Pakistan census |
| `city_area` | string | Tehsil name |
| `availability_status` | string | "online" (80%) or "offline" (20%) |
| `charges.base_rate` | int | Hourly rate in PKR (varies by service type) |
| `charges.travel_rate` | int | Travel cost per km (PKR 20–50) |
| `rating` | float | Weighted average rating (3.4–5.0) |
| `on_time_score` | float | Historical on-time arrival ratio (0.55–0.99) |
| `cancellation_risk` | float | Cancellation rate (0.01–0.25) |
| `capacity` | int | Max simultaneous jobs (2–5) |
| `active_jobs` | int | Current active jobs (reset to 0 at startup) |
| `total_reviews` | int | Lifetime review count |
| `total_jobs` | int | Lifetime completed jobs |

### Supported Service Types

| Job Role | Expertise Tags |
|---|---|
| AC Technician | ac_repair, ac_installation, ac_maintenance |
| Electrician | electrician, wiring, fan_repair, generator_repair |
| Plumber | plumber, pipe_fitting, drain_cleaning, motor_repair |
| Carpenter | carpenter, furniture_repair, door_fitting, cupboard_making |
| Cleaner | home_cleaning, deep_cleaning, sofa_cleaning, carpet_cleaning |
| Painter | wall_painting, house_painting, exterior_painting, polish_work |
| Gas Technician | gas_repair, gas_installation, geyser_repair, stove_repair |
| CCTV Technician | cctv_installation, security_systems, network_setup |
| Mechanic | car_repair, bike_repair, engine_work, puncture_repair |
| Solar Technician | solar_installation, solar_maintenance, inverter_repair |

---

## 7. Customer Dataset Schema

**File:** `backend/data/sessions.json` (runtime) + booking records

Customer location is resolved at runtime via the Nominatim geocoding API
from the location string they mention in the chat prompt (e.g. "F-7" →
`33.7196, 73.0551`). This is cached per session so it is only resolved once.

| Field | Type | Description |
|---|---|---|
| `customer_id` | string | Unique customer identifier |
| `session_id` | string | Active orchestration session |
| `parsed_intent.location` | string | Raw location string from prompt |
| `customer_lat` | float | Geocoded latitude (Nominatim) |
| `customer_lng` | float | Geocoded longitude (Nominatim) |

Customer location is used by the ProviderMatcher to calculate:
- Real travel distance from provider to customer (Haversine formula)
- Travel cost (distance × provider's `travel_rate`)
- Estimated travel time (distance / 30 km/h assumed city speed)

---

## 8. Job Schema

**File:** `backend/data/mock_bookings.json`

```json
{
  "booking_id": "BK-20250516-0001",
  "provider_id": "p00042",
  "provider_name": "Ali Rehman",
  "customer_id": "customer_001",
  "service_type": "plumber",
  "location": "F-7, Islamabad",
  "scheduled_time": "2025-05-17T10:00:00.000Z",
  "status": "ACCEPTED",
  "final_price": 1800,
  "checklist": [
    { "item": "Inspect pipe leak", "completed": false },
    { "item": "Replace fittings", "completed": false },
    { "item": "Test water flow", "completed": false }
  ],
  "current_lat": 33.7312,
  "current_lng": 73.0389,
  "customer_lat": 33.7196,
  "customer_lng": 73.0551,
  "distance_meters": 9600,
  "created_at": "2025-05-16T10:00:00.000Z",
  "state_history": [
    { "status": "PENDING_PROVIDER", "timestamp": "2025-05-16T10:00:00.000Z" },
    { "status": "ACCEPTED",         "timestamp": "2025-05-16T10:04:22.000Z" }
  ]
}
```

### Distance Accuracy

`distance_meters` is seeded directly from `provider.distance_km × 1000`
at booking creation — the same value displayed on the provider selection
card. Both use the same Nominatim-geocoded customer coordinates, so the
distance on the live tracking map exactly matches what was shown during
provider selection (e.g. a provider shown as "9.6 km away" starts the
simulation at exactly 9600 m).

---

## 9. Matching Algorithm — 8 Factors

The ProviderMatcher scores every eligible provider against 8 weighted
factors. Composite score ranges from 0 to 100.

```
Composite Score =
  (15% × Travel Time Score)        ← real haversine distance from geocoded coords
+ (15% × Availability Score)       ← online status + capacity
+ (20% × Specialisation Score)     ← service expertise match
+ (15% × On-Time Score)            ← historical reliability
+ (15% × Review Sentiment Score)   ← Gemini-analysed review quality
+ (10% × Rate Score)               ← price competitiveness vs market
+ (5%  × Cancellation Risk Score)  ← inverse of cancellation rate
+ (5%  × Capacity Score)           ← available job slots right now
```

### Geocoding in Matching

Before any scoring occurs, the customer's location string is resolved to
real GPS coordinates via the Nominatim API:

```
geocodeLocation("F-7, Islamabad")
  → Nominatim: GET /search?q=F-7,+Islamabad,+Pakistan&format=json
  → { lat: 33.7196, lng: 73.0551 }
  → cached in _geocodeCache for session lifetime
```

The resolved coordinates are then used in haversine calculations against
each provider's stored lat/lng. This means providers across all of
Pakistan are correctly ranked by actual distance from any location the
customer mentions — not just Islamabad sectors.

### Hard Exclusion Filters

Providers are removed from the candidate pool entirely if:
- `availability_status != "online"`
- `active_jobs >= capacity`
- `cancellation_risk > 0.30`
- `service_type` not in `service_expertise`
- Provider ID is in `session.providers_tried` (already shown or cancelled)

---

## 10. Job Status State Machine

```
             Customer selects provider
                       │
                       ▼
             ┌─────────────────────┐
             │  PENDING_PROVIDER   │ ← Awaiting provider response
             └────────┬────────────┘
                      │
            ┌─────────┴──────────┐
            │                    │
     Provider accepts      Provider cancels
            │                    │
            ▼                    ▼
    ┌────────────┐      ┌─────────────────────────┐
    │  ACCEPTED  │      │  CANCELLED_PROVIDER      │
    └─────┬──────┘      │  (stays on Active tab)   │
          │             └─────────┬───────────────┘
          ▼                       │
    ┌────────────┐      ┌─────────┴──────────────┐
    │  ARRIVING  │      │  Customer chooses:      │
    └─────┬──────┘      ├── Find New Provider     │
          │             │   → new session created │
          ▼             │   → excluded from match │
    ┌────────────┐      └── Cancel and End Chat   │
    │  ARRIVED   │          → CANCELLED_CUSTOMER  │
    └─────┬──────┘          → moves to History    │
          │ (checklist unlocked for provider)
          ▼
    ┌─────────────┐
    │ IN_PROGRESS │
    └──────┬──────┘
           │ (all checklist items ticked → Mark Complete)
           ▼
    ┌───────────┐
    │ COMPLETED │ ← ActiveSessionService cleared → customer can book again
    └───────────┘
```

### Status Definitions

| Status | Trigger | Customer Tab |
|---|---|---|
| `PENDING_PROVIDER` | Customer selects provider | Active |
| `ACCEPTED` | Provider accepts | Active |
| `ARRIVING` | GPS simulation starts | Active |
| `ARRIVED` | distance_meters < 50 | Active |
| `IN_PROGRESS` | Checklist items being ticked | Active |
| `COMPLETED` | Provider marks all done | History |
| `CANCELLED_PROVIDER` | Provider cancels | Active (until customer acts) |
| `CANCELLED_CUSTOMER` | Customer taps "Cancel and End Chat" | History |

### GPS Simulation

Provider coordinates are interpolated toward the customer at 1-second
intervals via the `/api/booking/simulate-step` endpoint:

```
Every 1 second:
  POST /api/booking/simulate-step { booking_id }
  → backend moves provider coords toward customer coords
  → distance_meters decreases
  → when distance_meters < 50 → status = ARRIVED

Customer LiveTrackingWidget polls every 2 seconds:
  GET /api/booking/:id
  → updates map with new provider position
  → bike icon moves toward customer house pin
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
| Provider accepted | Provider taps Accept | "[Provider Name] ne kaam accept kar liya!" |
| Provider cancelled | Provider cancels | "[Provider Name] ne cancel kar diya. Naya provider dhundh rahe hain." |
| Provider on the way | Status changes to Arriving | "[Provider Name] rawan ho gaye hain." |
| Job completed | Status changes to Completed | "Kaam mukammal ho gaya! Rating dein." |

---

## 12. APIs and Tools

### Backend REST API

**Base URL:** `http://localhost:3000`

#### Session & Orchestration

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/health` | Health check |
| `POST` | `/api/session/create` | Create new customer session |
| `GET` | `/api/session/:id` | Get full session state |
| `PATCH` | `/api/session/:id` | Update session (phase, parsed_intent, providers_tried) |
| `POST` | `/api/orchestrate` | Run full agent pipeline |

The `PATCH /api/session/:id` endpoint is used by the "Find New Provider"
flow to pre-configure a new session with:
- `phase: "thinking"` — skips intake, goes directly to matching
- `parsed_intent` — reconstructed from cancelled booking
- `providers_tried: [cancelled_provider_id]` — excludes the cancelled provider

#### Booking Management

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/bookings` | List all bookings |
| `GET` | `/api/booking/:id` | Get full booking record |
| `POST` | `/api/booking/status` | Update job status |
| `POST` | `/api/booking/simulate-step` | Advance GPS simulation by one step |
| `POST` | `/api/booking/checklist` | Mark checklist item complete |
| `POST` | `/api/booking/submit-rating` | Submit customer star rating |
| `POST` | `/api/booking/cancel-provider` | Provider cancels a job |

### External Tools and Services

| Tool | Purpose | Free? |
|---|---|---|
| `@google/genai` | Gemini API — intent parsing, ranking rationale | Free tier |
| Google Antigravity | Agent orchestration and plan execution | Hackathon access |
| Nominatim (OSM) | Geocoding location strings to GPS coordinates | Free, no key |
| `flutter_map` | OpenStreetMap map rendering in Flutter | Free, no key |
| `latlong2` | LatLng type for flutter_map | Free |
| Haversine formula | Distance between GPS coordinates | Custom — no Maps API |
| `dotenv` | Environment variable management | Free |

### Environment Variables

```env
PORT=3000
GEMINI_API_KEY=AIzaSy...    # Get free from aistudio.google.com
```

No Anthropic API. No OpenAI. No Google Maps API. No paid services beyond
the free Gemini tier.

---

## 13. Assumptions

**Location**
- Customer location is extracted from the natural language prompt and
  resolved to GPS coordinates at runtime via Nominatim (OpenStreetMap's
  geocoding API). The result is cached for the session lifetime.
- Provider locations are real GPS coordinates from Pakistani sub-tehsil
  data (Election Commission of Pakistan dataset), with ±0.005° jitter.
- Travel speed is assumed at 30 km/h average. No real traffic data.
- Arrival detected when `distance_meters < 50`.

**Providers**
- 50,960 mock providers cover all of Pakistan across 728 sub-tehsil
  locations and 10 service types.
- 80% of providers are "online", 20% are "offline" (realistic availability).
- Provider location is simulated — no real GPS hardware.

**Pricing**
- All prices are in Pakistani Rupees (PKR).
- Service charges cover labour only. Parts and equipment are excluded.
- Travel charges: `distance_km × provider.travel_rate`.
- Urgency surcharge: high → Rs. 200, medium → Rs. 100, low → Rs. 0.

**Session Management**
- Sessions expire after 30 minutes of inactivity.
- The frontend `ActiveSessionService` (in-memory) tracks pre-booking
  sessions so users can resume if they navigate away mid-conversation.
- Booking sessions persist until COMPLETED or CANCELLED_CUSTOMER.

**Notifications**
- Push notifications use Flutter's `local_notifications` (same device).
  Production would use Firebase Cloud Messaging.

---

## 14. Cost and Latency Analysis

### Gemini API Calls Per Session

| Step | Gemini call? | Avg tokens | Avg latency |
|---|---|---|---|
| IntentParser | Yes | ~800 in / ~300 out | 1,200 ms |
| Geocoding (Nominatim) | No (HTTP GET) | — | ~180 ms |
| ProviderMatcher (rationale) | Yes | ~600 in / ~150 out | 900 ms |
| BookingSimulator | No | — | < 30 ms |
| **Total per booking session** | **2 Gemini calls** | **~1,400 in / ~450 out** | **~2,300 ms** |

Geocoding adds ~180 ms on first call for a new location, then 0 ms from
cache. Provider matching across 50,960 providers is pure CPU work and
completes in < 100 ms (JS array filter + sort).

### End-to-End Latency

| Phase | Time |
|---|---|
| Intent parsing (Gemini) | 1,200 ms |
| Geocoding (Nominatim, first call) | 180 ms |
| Provider matching (50k providers, CPU) | < 100 ms |
| Matching rationale (Gemini) | 900 ms |
| Booking creation (async, geocode cached) | < 30 ms |
| **Total from user input to booking confirmation** | **~2,400 ms** |

---

## 15. Baseline Comparison

### Hazir vs Current Reality (WhatsApp/Phone)

| Capability | Current method | Hazir |
|---|---|---|
| Finding a provider | Manual calls, asking contacts | Automated in < 3 seconds |
| Price transparency | No reference point | Calculated from provider rates + industry standards |
| Provider trust signals | Word of mouth only | Rating, on-time score, cancellation risk |
| Scheduling | Verbal, often forgotten | Confirmed booking with reminders |
| Tracking provider | Call and ask "kahan ho?" | Live OpenStreetMap with bike icon |
| Location resolution | Manual area knowledge | Nominatim geocoding of any Pakistan location |
| Dispute resolution | No mechanism | Logged, cancellation risk updated |
| Language support | Works in any language | AI handles Urdu, Roman Urdu, English, mixed |

### Hazir vs Existing Pakistani Apps

| Capability | Rozee/OLX | TaskNow | Hazir |
|---|---|---|---|
| Informal sector focus | Partial | Yes | Yes |
| National coverage | Yes | Partial | Yes — 728 sub-tehsils |
| Multilingual AI (Roman Urdu) | No | No | Yes |
| Real-time provider matching | No | Basic | 8-factor scored |
| Conversational interface | No | No | Yes — full chat |
| Live map tracking | No | No | Yes — OpenStreetMap |
| Real geocoding | No | Partial | Yes — Nominatim |
| Agentic reasoning trace | No | No | Yes — full Antigravity log |
| Session resume after navigation | No | No | Yes — background save |

---

## 16. Privacy Note

**Data collected**
- Customer: session ID, GPS coordinates derived from location prompt
- Provider: name, GPS coordinates, job role, service expertise
- Job records: booking ID, service type, location string, charges

**Data not collected**
- No phone numbers stored
- No payment card or banking information
- No personal identification documents
- No photos or video

**Data storage**
- All data stored locally in JSON flat files in `/backend/data/`.
- Nominatim geocoding sends only the location string (e.g. "F-7") — no
  personal data is transmitted. Nominatim's privacy policy applies.

**Gemini data usage**
- Text sent to Gemini contains only the service request description.
  No personally identifiable information is included in any Gemini prompt.

---

## 17. Limitations

**No real GPS hardware**
Provider location is simulated. Production would use Flutter's
`geolocator` package with provider consent.

**No real push notifications**
Uses Flutter `local_notifications` (same device). Production needs FCM.

**No payment processing**
Charges are calculated and displayed but not processed. Production would
integrate JazzCash or EasyPaisa.

**Nominatim rate limits**
Nominatim allows 1 request/second with a valid User-Agent. For demo use
this is fine. Production would cache geocodes in a database and use a
commercial geocoding provider for scale.

**Single server, no scaling**
Express backend with JSON flat files. Production needs PostgreSQL + Redis.

**No SMS fallback**
Production would need SMS for providers with low-end phones.

---

## 18. How to Run

### Prerequisites

- Node.js v18 or above
- Flutter SDK 3.x
- A free Google Gemini API key from [aistudio.google.com](https://aistudio.google.com)

### Backend

```bash
cd ai-service-orchestrator/backend

# Install dependencies
npm install

# Create environment file
cp .env.example .env
# Edit .env: GEMINI_API_KEY=AIzaSy...

# Start development server
npm run dev
# Server starts at http://localhost:3000
```

### Frontend

```bash
cd frontend

# Install Flutter dependencies
flutter pub get

# Run on Chrome (web demo mode)
flutter run -d chrome

# Run on Android
flutter run -d android
```

### Verify the Connection

Open the app and type in the chat:

```
mujhe f7 mein plumber chahiye kal sham
```

The AI resolves "f7" to real F-7, Islamabad coordinates via Nominatim,
finds providers near that location from the 50,960-provider dataset,
and returns 3 ranked matches within ~2.5 seconds. The distance shown on
each provider card matches the distance that will appear in live tracking.

### Demo Scenarios

**Scenario 1 — Happy path (Roman Urdu, AC repair, Islamabad)**
```
Input: "AC bilkul kaam nahi, kal subah G-13 mein chahiye"
Flow: Geocode G-13 → match AC technicians → select provider →
      live map shows bike at exact provider.distance_km from G-13 pin →
      bike animates toward customer location every 1 second →
      checklist unlocks on ARRIVED → complete → rating form
```

**Scenario 2 — Provider cancels, rematch with context**
```
Input: Any booking
Action: Provider taps Cancel
Customer sees:
  "Find New Provider" → new chat with full conversation history restored
                        cancelled provider excluded from results
  OR
  "Cancel and End Chat" → booking moves to History, can start fresh
```

**Scenario 3 — English input, any Pakistan city**
```
Input: "I need a plumber for pipe leakage in Johar Town Lahore today"
Flow: Nominatim geocodes "Johar Town, Lahore" → haversine against all
      50,960 providers → Lahore-area plumbers ranked by real distance
```

**Scenario 4 — User goes back mid-load**
```
User types prompt → navigates back before AI responds
→ Orchestration continues in background
→ Home screen shows "Resume Chat" when result arrives
→ Tap Resume → full conversation with provider results restored
```

---

## 19. Recent Improvements

The following features and fixes were implemented after the initial hackathon
submission, reflecting real UX testing feedback.

### Provider Dataset
- **50,960 providers** generated from 728 Pakistani sub-tehsil locations
  using `sub_tehsils_pakistan.csv` (Election Commission of Pakistan data).
  Replaces the original 20 hand-crafted Islamabad-only providers.
- Script: `backend/data/generate_providers.py`

### Real Geocoding (No Hardcoded Coordinates)
- **Frontend**: `_ProviderMapView` is now a `StatefulWidget` that calls
  Nominatim at runtime. Location strings like "f7", "F-7", "F 7 Islamabad"
  all resolve correctly. Results cached in a static map across widget rebuilds.
- **Backend ProviderMatcher**: `geocodeLocation()` exported and shared.
  All provider matching uses real geocoded customer coordinates.
- **Backend BookingSimulator**: `createBooking()` made `async` and uses
  the same `geocodeLocation()` (already cached) instead of the old hardcoded
  lookup table. `distance_meters` is seeded from `provider.distance_km × 1000`
  so the live tracking distance exactly matches the provider card.

### Live Map Tracking
- Replaced the linear progress bar with an actual **OpenStreetMap map**
  (`flutter_map` + `latlong2`, no API key required).
- Customer location: dark green house pin at geocoded coordinates.
- Provider location: green bike icon, placed at `distance_meters` away
  in the NW direction from the customer, moving toward the house every 1 second.
- Green polyline drawn between bike and house.
- Pinch-to-zoom enabled. Map is embedded in the chat scroll view.

### UX Flow
- **Dynamic AppBar titles**: Customer chat shows service name (e.g. "Plumbing")
  instead of "New Booking". Provider chat shows job name instead of logo.
- **Button locking**: All chips, "Select Provider", "More Options",
  "Haan samajh gaya", "Accept", "Decline" are permanently disabled after
  one tap — prevents accidental double-actions.
- **Chat input hidden**: Customer chat input disappears after booking confirmed.
  Provider chat input is hidden throughout (interaction via buttons only).
- **Back buttons removed**: Tab screens (Bookings, Alerts, Profile, Dashboard,
  Jobs) no longer show a back button. Back button retained on chat screens only.
- **Chat history preserved**: Full conversation (chips, AI responses, buttons)
  saved to `ChatHistoryService` keyed by `booking_id`. Restored when opening
  a booking from the Bookings tab.

### Session & Active Booking Management
- `ActiveSessionService` (in-memory) tracks the current open session from
  the moment a session is created — not just after booking confirmation.
- Home screen checks `ActiveSessionService` + API on every tab switch.
  Shows "Active Booking" or "Ongoing Conversation" banner. New chat prompt
  is hidden until the current session is resolved.
- "Abandon and start new chat" link shown for pre-booking sessions (no
  confirmed booking yet), allowing the user to discard and restart.
- Session messages auto-saved in `dispose()` (thinking bubbles stripped).
  If user navigates back mid-request, orchestration completes in background
  and result saved — "Resume Chat" appears on home screen.

### Provider Cancellation Flow
- `CANCELLED_PROVIDER` added to the Active booking statuses. Booking stays
  on the Active tab until the customer explicitly acts.
- Two-option UI: **Find New Provider** (rematches with context, excludes
  cancelled provider) and **Cancel and End Chat** (sets `CANCELLED_CUSTOMER`,
  moves to History).
- "Find New Provider" pre-configures a new backend session with
  `phase: "thinking"`, the original `parsed_intent` from the booking,
  and `providers_tried: [cancelled_provider_id]`. The orchestrator skips
  intake and goes directly to matching, excluding the cancelled provider.
  Full prior conversation is restored via `ChatHistoryService`.

### Checklist Timing
- Provider checklist is **not shown** on ACCEPTED or ARRIVING.
- Provider chat polls booking status every 2 seconds after accepting.
- Checklist appears automatically when status reaches ARRIVED.

### Simulation Speed
- GPS simulation step timer: **1 second** (was 3 seconds).
- Customer status poll timer: **2 seconds** (was 3 seconds).
- Provider status poll timer: **2 seconds**.

---

## Team

Built for the Google Antigravity Hackathon — Challenge 2: AI Service
Orchestrator for Informal Economy.

App: **Hazir** — حاضر — "Present. Ready. Here for you."

---

*Hazir uses Google Gemini Pro via Antigravity for all AI reasoning.
No other LLM is used. All prices in PKR.*
