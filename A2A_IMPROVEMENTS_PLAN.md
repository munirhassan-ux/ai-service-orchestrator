# A2A Improvements — Implementation Plan

Two features. ~1.5 hours total. Zero new Gemini API calls (all deterministic logic).

---

## Background

This is a Node.js/TypeScript backend (`backend/src/`) with a Flutter web frontend (`frontend/lib/`). The backend runs on port 3000 via `tsx watch`. The two features below make the agent-to-agent communication more realistic.

**Key files to understand before starting:**
- `backend/src/agents/bookingSimulator.ts` — booking lifecycle, status transitions, `submitBookingRating()`
- `backend/src/agents/progressAgent.ts` — writes A2A narrative messages to `booking.agent_messages[]` when job status changes
- `backend/src/agents/reliabilityEngine.ts` — EWMA score engine, `applyEvent()` updates provider scores
- `backend/src/index.ts` — Express app startup, the place to mount the SLA polling interval

---

## Feature 1: Customer Agent Payment Verification (~30 min)

### What it does
Right now, when a provider marks a job COMPLETED, `progressAgent.ts` auto-appends a `customer_agent` payment confirmation message 500ms later — no checks, no gate. This should be replaced with a real two-step flow:

1. When COMPLETED fires → Provider Agent says "kaam ho gaya, payment confirm karo"
2. The 500ms auto-payment message is **removed**
3. When the **customer submits a rating** → Customer Agent verifies checklist is complete, then releases payment

### Changes

#### File 1: `backend/src/agents/progressAgent.ts`

**In the `COMPLETED` case of `buildMessage()` (around line 54):**

Remove the second message (the auto `PAYMENT_CONFIRMED` one). Also make the provider_agent message smarter — if checklist items aren't all done, say so.

Replace the entire `case "COMPLETED":` block with this:

```typescript
case "COMPLETED": {
  const allDone = !b.checklist || b.checklist.length === 0 || b.checklist.every((i: any) => i.completed);
  const unpaid  = b.checklist?.filter((i: any) => !i.completed).map((i: any) => i.item) ?? [];

  const providerMsg = allDone
    ? `Kaam mukammal ho gaya ✅ Tamam checklist items complete hain. Meherbani kar ke payment Rs. ${price} confirm karein aur rating dein taakay funds release ho sakain.`
    : `Kaam mukammal mark kar diya hai lekin ${unpaid.length} item(s) abhi incomplete hain: ${unpaid.join(", ")}. Payment abhi hold hai.`;

  return [{
    from: "provider_agent", to: "customer_agent", status,
    message: providerMsg,
    timestamp: new Date().toISOString(),
  }];
}
```

The key change: only **one** message (provider_agent), no 500ms auto-payment.

---

#### File 2: `backend/src/agents/bookingSimulator.ts`

**In `submitBookingRating()` (around line 502), after `writeBookings(data)` and before `return booking`:**

Add the payment release logic:

```typescript
// Customer Agent verifies checklist and releases payment
const allItemsDone = booking.checklist.every(c => c.completed);
const paymentMsg: any = allItemsDone
  ? {
      from: "customer_agent",
      to: "provider_agent",
      status: "PAYMENT_CONFIRMED",
      message: `Rs. ${booking.final_price} — tamam checklist items complete hain aur rating submit ho gayi. Payment release ho gayi. Shukriya! ⭐${stars}`,
      timestamp: new Date().toISOString(),
    }
  : {
      from: "customer_agent",
      to: "provider_agent",
      status: "PAYMENT_HELD",
      message: `Rs. ${booking.final_price} — payment abhi hold hai. Checklist mein kuch items incomplete hain. Please complete karein.`,
      timestamp: new Date().toISOString(),
    };

if (!booking.agent_messages) booking.agent_messages = [];
booking.agent_messages.push(paymentMsg);
writeBookings(data);  // write again to persist the new message
```

> **Note:** `writeBookings(data)` is already called once above in this function. This second call is intentional — it writes the payment message to disk after the rating data is already saved.

---

### Result
- COMPLETED → provider_agent says "please confirm payment and rate"
- Customer submits rating → customer_agent checks checklist → releases (or holds) payment
- Zero Gemini calls. Pure logic.

---

## Feature 2: Post-Booking SLA Monitoring Agent (~45–60 min)

### What it does
After a booking is accepted, nothing currently watches whether the provider shows up. This feature adds a server-side polling loop that:

- For **immediate bookings** (scheduled within the next 3 hours): if status stays `ACCEPTED` for >25 min, alerts the customer. If >50 min, marks as no-show, fires reliability penalty.
- For **scheduled/future bookings**: starting 30 min before `scheduled_time`, if status is still `SCHEDULED` at `scheduled_time + 20 min`, marks as no-show.

### Changes

#### File 1: Create `backend/src/agents/slaMonitor.ts` (new file)

```typescript
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { applyEvent } from "./reliabilityEngine.js";
import { updateBookingStatus, getBooking } from "./bookingSimulator.js";
import { pushNotification } from "../notifications.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const bookingsFile = path.join(__dirname, "../../data/mock_bookings.json");

const WARN_AFTER_MIN  = 25;  // warn customer after 25 min silence
const NOSHOW_AFTER_MIN = 50; // mark no-show after 50 min silence (immediate bookings)
const FUTURE_GRACE_MIN = 20; // scheduled bookings: grace period after scheduled_time

const warnedBookings  = new Set<string>(); // track who already got a warning this interval
const noshowBookings  = new Set<string>(); // track who was already marked no-show

function readBookings(): any[] {
  try { return JSON.parse(fs.readFileSync(bookingsFile, "utf-8")).bookings; }
  catch { return []; }
}

function appendAgentMessage(bookingId: string, message: any) {
  try {
    const raw  = JSON.parse(fs.readFileSync(bookingsFile, "utf-8"));
    const idx  = raw.bookings.findIndex((b: any) => b.booking_id === bookingId);
    if (idx === -1) return;
    if (!raw.bookings[idx].agent_messages) raw.bookings[idx].agent_messages = [];
    raw.bookings[idx].agent_messages.push(message);
    fs.writeFileSync(bookingsFile, JSON.stringify(raw, null, 2));
  } catch { /* non-fatal */ }
}

export function startSlaMonitor(): void {
  setInterval(() => {
    const now      = Date.now();
    const bookings = readBookings();

    for (const b of bookings) {
      if (noshowBookings.has(b.booking_id)) continue;

      const isActiveAccepted  = b.status === "ACCEPTED";
      const isActiveScheduled = b.status === "SCHEDULED";
      if (!isActiveAccepted && !isActiveScheduled) continue;

      const scheduledMs = new Date(b.scheduled_time).getTime();
      const lastChange  = new Date(b.updated_at).getTime();
      const minutesSinceLastChange = (now - lastChange) / 60_000;
      const minutesPastScheduled   = (now - scheduledMs) / 60_000;

      if (isActiveAccepted) {
        // Immediate or near-term booking stuck in ACCEPTED

        if (!warnedBookings.has(b.booking_id) && minutesSinceLastChange >= WARN_AFTER_MIN) {
          warnedBookings.add(b.booking_id);
          console.log(`[SlaMonitor] Warning: ${b.booking_id} stuck ACCEPTED for ${Math.round(minutesSinceLastChange)} min`);

          appendAgentMessage(b.booking_id, {
            from: "customer_agent",
            to: "provider_agent",
            status: "SLA_WARNING",
            message: `Provider se abhi tak koi update nahi mila — ${Math.round(minutesSinceLastChange)} minute guzar gaye hain. Kya aap theek hain? Please status update karein.`,
            timestamp: new Date().toISOString(),
          });

          pushNotification(
            "CUSTOMER", b.booking_id, "sla_warning",
            "Provider Ka Koi Jawab Nahi ⚠️",
            `${b.provider_name} ne ${Math.round(minutesSinceLastChange)} minute se koi update nahi di. Hum monitor kar rahe hain.`
          );
        }

        if (minutesSinceLastChange >= NOSHOW_AFTER_MIN) {
          noshowBookings.add(b.booking_id);
          console.log(`[SlaMonitor] No-show: ${b.booking_id} — marking CANCELLED_TIMEOUT`);

          try { applyEvent(b.provider_id, "no_show", b.booking_id); } catch { /* non-fatal */ }
          updateBookingStatus(b.booking_id, "CANCELLED_TIMEOUT");

          appendAgentMessage(b.booking_id, {
            from: "customer_agent",
            to: "provider_agent",
            status: "SLA_BREACH",
            message: `SLA breach: provider ne ${Math.round(minutesSinceLastChange)} minute mein koi response nahi diya. Booking automatically cancel ho gayi hai aur reliability score update ho gaya hai.`,
            timestamp: new Date().toISOString(),
          });

          pushNotification(
            "CUSTOMER", b.booking_id, "sla_breach",
            "Booking Cancel — Provider No-Show 🚫",
            `${b.provider_name} ne respond nahi kiya. Booking cancel ho gayi. Hum naya provider dhundhne ki koshish karein ge.`
          );
        }

      } else if (isActiveScheduled && minutesPastScheduled >= FUTURE_GRACE_MIN) {
        // Future booking where scheduled time has passed but provider hasn't moved
        noshowBookings.add(b.booking_id);
        console.log(`[SlaMonitor] Scheduled no-show: ${b.booking_id} — ${Math.round(minutesPastScheduled)} min past scheduled_time`);

        try { applyEvent(b.provider_id, "no_show", b.booking_id); } catch { /* non-fatal */ }
        updateBookingStatus(b.booking_id, "CANCELLED_TIMEOUT");

        appendAgentMessage(b.booking_id, {
          from: "customer_agent",
          to: "provider_agent",
          status: "SLA_BREACH",
          message: `Scheduled time guzar gaya — provider ne ${Math.round(minutesPastScheduled)} minute baad bhi status update nahi ki. Booking cancel ho gayi.`,
          timestamp: new Date().toISOString(),
        });

        pushNotification(
          "CUSTOMER", b.booking_id, "sla_breach",
          "Provider Waqt Par Nahi Aaya 🚫",
          `${b.provider_name} scheduled time ke ${Math.round(minutesPastScheduled)} minute baad bhi appear nahi hua. Booking cancel ho gayi.`
        );
      }
    }
  }, 2 * 60 * 1000); // runs every 2 minutes

  console.log("[SlaMonitor] Started — checking every 2 min");
}
```

---

#### File 2: `backend/src/index.ts`

Import and start the SLA monitor at the bottom of the `app.listen(...)` callback (after the startup reset block):

**Add this import at the top of the file (with the other imports):**
```typescript
import { startSlaMonitor } from "./agents/slaMonitor.js";
```

**Add this line inside `app.listen(PORT, () => { ... })`, after the `console.log("🧹 Job listings cleared...")` line:**
```typescript
startSlaMonitor();
```

That's it. The monitor auto-starts on every backend restart alongside the existing startup logic.

---

### Edge cases to be aware of

1. **`warnedBookings` and `noshowBookings` are in-memory sets.** They reset on backend restart (which is fine since `mock_bookings.json` is also cleared on restart). They won't double-warn within a single server session.

2. **The `CANCELLED_TIMEOUT` status** — check that the Flutter frontend handles this gracefully. Search for `CANCELLED_PROVIDER` in the customer chat screen; wherever that's handled, add `CANCELLED_TIMEOUT` to the same branch.
   - File: `frontend/lib/screens/customer/chat_screen.dart`
   - Search for: `CANCELLED_PROVIDER`
   - Make sure the same UI treatment applies to `CANCELLED_TIMEOUT`

3. **Demo timing** — 25 min and 50 min thresholds are realistic but long for a demo. For demo purposes you can drop them to 3 min and 6 min:
   ```typescript
   const WARN_AFTER_MIN  = 3;
   const NOSHOW_AFTER_MIN = 6;
   ```
   Just remember to put them back for production.

4. **Polling interval** is 2 minutes. For a demo with reduced thresholds, change it to 30 seconds:
   ```typescript
   }, 30 * 1000);
   ```

---

## Testing Checklist

After implementing both features:

### Feature 1 (Payment gate)
- [ ] Book a job, walk it through to COMPLETED
- [ ] Check that the `agent_messages` array in the booking has only ONE message at COMPLETED (the provider_agent one), NOT two
- [ ] Submit a rating via the customer app
- [ ] Check that `agent_messages` now has a second entry with `status: "PAYMENT_CONFIRMED"` or `"PAYMENT_HELD"`
- [ ] Test with a booking where not all checklist items are ticked — confirm the provider_agent message mentions the incomplete items

### Feature 2 (SLA monitor)
- [ ] Start the backend and check logs show `[SlaMonitor] Started — checking every 2 min`
- [ ] Book a job, then wait (or drop thresholds to 3/6 min for demo) — do NOT click any provider actions
- [ ] After WARN_AFTER_MIN: check that `[SlaMonitor] Warning` appears in backend logs, a warning notification fires, and an `SLA_WARNING` message appears in `agent_messages`
- [ ] After NOSHOW_AFTER_MIN: check that booking status becomes `CANCELLED_TIMEOUT` in `mock_bookings.json`
- [ ] Check provider's `cancellation_risk` in `mock_providers.json` went up (reliability engine fired `no_show`)
- [ ] Check that the customer UI doesn't crash on `CANCELLED_TIMEOUT` status

---

## File Summary

| File | Action | Change |
|------|--------|--------|
| `backend/src/agents/progressAgent.ts` | Edit | Replace COMPLETED case — remove auto-payment, add checklist awareness |
| `backend/src/agents/bookingSimulator.ts` | Edit | In `submitBookingRating()` — append PAYMENT_CONFIRMED after rating saved |
| `backend/src/agents/slaMonitor.ts` | **Create new** | Full SLA monitor agent |
| `backend/src/index.ts` | Edit | Import + start SLA monitor on startup |
| `frontend/lib/screens/customer/chat_screen.dart` | Edit | Handle `CANCELLED_TIMEOUT` same as `CANCELLED_PROVIDER` |
