import { Router, Request, Response } from "express";
import { runOrchestration, confirmBookingAfterNegotiation, rerouteToNextProvider, triggerWarmRestart } from "../orchestrator.js";
import { providerRespond, customerRespond, acceptMidpoint, declineMidpoint, getThread } from "../agents/negotiationAgent.js";
import { updateBookingStatus, completeChecklistItem, getBooking, submitBookingRating, handleProviderCancellation } from "../agents/bookingSimulator.js";
import { matchProviders } from "../agents/providerMatcher.js";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
import { processDispute, raiseDispute, getDispute, listDisputes, respondToDispute } from "../agents/disputeAgent.js";
import { getReliabilitySnapshot, applyEvent } from "../agents/reliabilityEngine.js";
import { getContract, appendEventToContract } from "../agents/negotiationEngine.js";
import { createSession, getSession, updateSession } from "../session.js";
import { redact, checkOutput } from "../middleware/guardrail.js";
import { logTraceEvent } from "../trace.js";
import { logOutputSafety } from "../logger.js";
import { pushNotification, notificationsQueue } from "../notifications.js";

const router = Router();

// ── SESSION MANAGEMENT ─────────────────────────────────────
router.post("/session/create", (req: Request, res: Response) => {
  const { customer_id } = req.body;
  try {
    const session = createSession(customer_id || "customer_001");
    return res.json(session);
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

router.get("/session/:id", (req: Request, res: Response) => {
  try {
    const session = getSession(req.params.id);
    if (!session) return res.status(404).json({ error: "Session not found" });
    return res.json(session);
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

router.patch("/session/:id", (req: Request, res: Response) => {
  try {
    const session = updateSession(req.params.id, req.body);
    return res.json(session);
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// GET /api/session/:id/privacy-log — returns redaction audit log for this session
router.get("/session/:id/privacy-log", (req: Request, res: Response) => {
  try {
    const session = getSession(req.params.id);
    if (!session) return res.status(404).json({ error: "Session not found" });
    return res.json({
      session_id: session.session_id,
      privacy_log: (session as any).privacy_log || [],
      safety_strikes: (session as any).safety_strikes || 0,
    });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// POST /api/guardrail/check — demo endpoint: redact arbitrary text and return result
router.post("/guardrail/check", (req: Request, res: Response) => {
  const { text } = req.body;
  if (!text) return res.status(400).json({ error: "text required" });
  const result = redact(String(text));
  return res.json(result);
});

// ── POST /api/orchestrate ──────────────────────────────────
// Main entry: takes user text, runs full pipeline
router.post("/orchestrate", async (req: Request, res: Response) => {
  const { input, customer_id, job_count, history, session_id } = req.body;
  if (!input && !session_id) return res.status(400).json({ error: "input or session_id required" });

  const customerId = customer_id || "customer_001";
  const userJobCount = job_count || 0;

  try {
    const result = await runOrchestration(input || "", customerId, userJobCount, history || [], session_id);

    // Output safety: scan Gemini's reply before it reaches the client
    if (result.message) {
      const outputCheck = checkOutput(result.message);
      logOutputSafety(outputCheck.safe, outputCheck.reason);
      if (!outputCheck.safe) {
        result.message = "Maafi chahta hoon, ek masla aa gaya. Dobara try karein.";
        (result as any).output_safety_violation = true;
        (result as any).output_safety_reason = outputCheck.reason;
      }
    }

    return res.json(result);
  } catch (err: any) {
    console.error("[API] /orchestrate error:", err);
    return res.status(500).json({ error: err.message });
  }
});

// ── POST /api/negotiate/timeout ───────────────────────────
// Trigger simulated provider timeout and automatically move to next provider
router.post("/negotiate/timeout", async (req: Request, res: Response) => {
  const { session_id } = req.body;
  if (!session_id) return res.status(400).json({ error: "session_id is required" });

  try {
    const session = getSession(session_id);
    if (!session) return res.status(404).json({ error: "Session not found" });

    const failedProvider = session.matched_providers[session.current_provider_index];
    logTraceEvent(session_id, {
      agent: "Orchestrator",
      provider_timeout: { provider_id: failedProvider.provider_id, timeout_seconds: 30 },
      gemini_decision: `Simulated timeout triggered for provider ${failedProvider.name}`
    });

    const result = await triggerWarmRestart(session, []);
    return res.json(result);
  } catch (err: any) {
    console.error("[API] /negotiate/timeout error:", err);
    return res.status(500).json({ error: err.message });
  }
});

// ── POST /api/negotiate/provider ──────────────────────────
// Provider: accept | decline | counter
router.post("/negotiate/provider", async (req: Request, res: Response) => {
  const { thread_id, action, counter_price, reason } = req.body;
  if (!thread_id || !action) return res.status(400).json({ error: "thread_id and action required" });

  try {
    const thread = await providerRespond(thread_id, action, counter_price, reason);
    return res.json({ status: "ok", thread });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── POST /api/negotiate/customer ──────────────────────────
// Customer: accept | decline | counter
router.post("/negotiate/customer", async (req: Request, res: Response) => {
  const { thread_id, action, counter_price } = req.body;
  if (!thread_id || !action) return res.status(400).json({ error: "thread_id and action required" });

  try {
    let thread = await customerRespond(thread_id, action, counter_price);
    
    // AUTO-SIMULATION: If customer countered, let the provider (AI) respond immediately
    if (action === "counter" && thread.status === "pending_provider") {
      const lastPrice = thread.messages[thread.messages.length - 1].offered_price;
      
      // AI Provider logic: If price is within 15% of AI quote, accept it!
      const diff = Math.abs(lastPrice - thread.ai_quote) / thread.ai_quote;
      if (diff <= 0.15) {
        thread = await providerRespond(thread_id, "accept");
      } else {
        thread = await providerRespond(thread_id, "counter", Math.round(thread.ai_quote * 0.95));
      }
    }

    return res.json({ status: "ok", thread });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── POST /api/negotiate/accept-midpoint ───────────────────
router.post("/negotiate/accept-midpoint", async (req: Request, res: Response) => {
  const { thread_id, accepted_by } = req.body;

  try {
    const thread = acceptMidpoint(thread_id, accepted_by);

    // If both agreed, trigger booking
    if (thread.status === "agreed" && thread.final_price) {
      return res.json({ status: "agreed", final_price: thread.final_price, thread });
    }

    return res.json({ status: "awaiting_other_party", thread });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── POST /api/negotiate/decline-midpoint ──────────────────
router.post("/negotiate/decline-midpoint", async (req: Request, res: Response) => {
  const { thread_id, declined_by, intent, match_result } = req.body;
  if (!thread_id || !declined_by) return res.status(400).json({ error: "thread_id and declined_by required" });

  try {
    const thread = declineMidpoint(thread_id, declined_by);

    // Automatic rerouting if intent and match_result are provided
    if (intent && match_result) {
      const result = await rerouteToNextProvider(intent, match_result, thread.provider_id);
      return res.json({ status: "rerouted", result });
    }

    return res.json({ status: "abandoned", thread });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── GET /api/negotiate/:thread_id ─────────────────────────
router.get("/negotiate/:thread_id", (req: Request, res: Response) => {
  const thread = getThread(req.params.thread_id);
  if (!thread) return res.status(404).json({ error: "Thread not found" });
  return res.json(thread);
});

// ── POST /api/booking/confirm ─────────────────────────────
// Called after negotiation agrees — creates the actual booking
router.post("/booking/confirm", async (req: Request, res: Response) => {
  const { intent, provider, price_quote, final_price, negotiation_thread_id, customer_id } = req.body;

  try {
    const { booking, trace } = await confirmBookingAfterNegotiation(
      intent,
      provider,
      price_quote,
      final_price,
      negotiation_thread_id,
      customer_id
    );
    return res.json({ status: "confirmed", booking, trace });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── POST /api/booking/status ──────────────────────────────
// caller_id must match the booking's customer_id or provider_id.
// Each role may only set statuses appropriate to their side.
const CUSTOMER_ALLOWED = new Set(["CANCELLED_CUSTOMER"]);
const PROVIDER_ALLOWED = new Set(["ACCEPTED", "CANCELLED_PROVIDER", "ARRIVING", "ARRIVED", "IN_PROGRESS", "COMPLETED"]);

router.post("/booking/status", (req: Request, res: Response) => {
  const { booking_id, status, caller_id } = req.body;
  if (!booking_id || !status) return res.status(400).json({ error: "booking_id and status required" });
  if (!caller_id)             return res.status(403).json({ error: "caller_id required" });

  const existing = getBooking(booking_id);
  if (!existing) return res.status(404).json({ error: "Booking not found" });

  const isCustomer = existing.customer_id === caller_id;
  const isProvider = existing.provider_id === caller_id;

  if (!isCustomer && !isProvider)
    return res.status(403).json({ error: "Not authorised for this booking" });

  if (isCustomer && !CUSTOMER_ALLOWED.has(status))
    return res.status(403).json({ error: `Customer cannot set status '${status}'` });

  if (isProvider && !PROVIDER_ALLOWED.has(status))
    return res.status(403).json({ error: `Provider cannot set status '${status}'` });

  try {
    const booking = updateBookingStatus(booking_id, status);
    return res.json({ status: "updated", booking });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── POST /api/booking/checklist ───────────────────────────
router.post("/booking/checklist", (req: Request, res: Response) => {
  const { booking_id, item_index } = req.body;
  try {
    const booking = completeChecklistItem(booking_id, item_index);
    return res.json({ status: "updated", booking });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── GET /api/booking/:id ──────────────────────────────────
router.get("/booking/:id", (req: Request, res: Response) => {
  const booking = getBooking(req.params.id);
  if (!booking) return res.status(404).json({ error: "Booking not found" });

  let providerObj: any = null;
  try {
    const providersFile = path.join(__dirname, "../../data/mock_providers.json");
    const providers = JSON.parse(fs.readFileSync(providersFile, "utf-8"));
    providerObj = providers.find((p: any) => p.provider_id === booking.provider_id);
  } catch (err) {
    console.error("Error reading provider for job detail mapping:", err);
  }

  if (!providerObj) {
    providerObj = {
      provider_id: booking.provider_id,
      name: booking.provider_name,
      location: { latitude: booking.current_lat || 33.6844, longitude: booking.current_lng || 73.0479 },
      city: "Islamabad",
      availability_status: "online",
      charges: { base_rate: booking.price_quote?.base_rate || 500, travel_rate: 30 },
      job_role: booking.service_type === "plumber" ? "Plumber" : "Technician",
      service_expertise: [booking.service_type],
      rating: 4.5,
      on_time_score: 0.9,
      cancellation_risk: 0.0,
      capacity: 3,
      active_jobs: 1
    };
  }

  const customerObj = {
    customer_id: booking.customer_id || "customer_001",
    name: "Munir Hassan",
    city: "Islamabad",
    location: {
      latitude: booking.customer_lat || 33.6844,
      longitude: booking.customer_lng || 73.0551
    }
  };

  const service_fee = (booking.price_quote?.base_rate || 500) * 2;
  const travel_charges = booking.price_quote?.distance_fee || 0;
  const on_demand_charges = booking.price_quote?.urgency_surcharge || 0;

  const jobDetail = {
    ...booking,
    customer: customerObj,
    provider: providerObj,
    service_type: booking.service_type,
    problem_description: booking.price_quote?.fairness_note || "Urgent repair request",
    time_to_arrive: booking.scheduled_time,
    estimated_duration_mins: 120,
    charges: {
      service_fee,
      travel_charges,
      on_demand_charges,
      total: booking.final_price
    }
  };

  // Attach A2A negotiation trace from contracts file if a contract exists for this booking
  try {
    const contractsFile = path.join(__dirname, "../../data/mock_contracts.json");
    if (fs.existsSync(contractsFile)) {
      const contracts: any[] = JSON.parse(fs.readFileSync(contractsFile, "utf-8"));
      const contract = contracts.find((c: any) => c.booking_id === booking.booking_id);
      if (contract) {
        (jobDetail as any).contract_id = contract.contract_id;
        const allBids: any[] = contract.cfp_log ?? [];

        // Load provider names for lookup
        const providersFile = path.join(__dirname, "../../data/mock_providers.json");
        const providersList: any[] = fs.existsSync(providersFile)
          ? JSON.parse(fs.readFileSync(providersFile, "utf-8")).providers ?? []
          : [];
        const nameOf = (id: string) =>
          providersList.find((p: any) => p.provider_id === id)?.name ?? id;

        (jobDetail as any).negotiation_trace = {
          phase: "negotiation",
          cfp_sent_to: allBids.map((b: any) => b.provider_id),
          proposals: allBids
            .filter((b: any) => b.accepted)
            .map((b: any) => ({
              provider:      b.provider_id,
              provider_name: nameOf(b.provider_id),
              price:         b.price,
              eta_min:       b.eta_min,
              confidence:    b.confidence,
            })),
          rounds:   contract.negotiation_rounds ?? 1,
          outcome:  "deal_locked",
          contract_id: contract.contract_id,
        };
      }
    }
  } catch (_) {}

  return res.json(jobDetail);
});

// ── POST /api/dispute ─────────────────────────────────────
router.post("/dispute", async (req: Request, res: Response) => {
  const { booking_id, provider_id, issue_type, comment } = req.body;
  if (!booking_id || !provider_id || !issue_type) {
    return res.status(400).json({ error: "booking_id, provider_id, and issue_type required" });
  }

  try {
    const result = await processDispute(booking_id, provider_id, issue_type, comment || "");

    // Also mark the booking as disputed
    updateBookingStatus(booking_id, "disputed" as any);

    const disputedBooking = getBooking(booking_id);
    if (disputedBooking?.session_id) {
      logTraceEvent(disputedBooking.session_id, {
        agent: "DisputeAgent",
        phase_after: "dispute_resolved",
        booking_id,
        provider_id,
        issue_type,
        resolution: (result as any).resolution || JSON.stringify(result),
      });
    }

    return res.json({ status: "dispute_logged", result });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── GET /api/trace/session/:session_id ───────────────────
// Retrieve full JSON trace for a session
router.get("/trace/session/:session_id", (req: Request, res: Response) => {
  const traceFile = path.join(__dirname, "../../data/agent_traces", `${req.params.session_id}.json`);
  if (!fs.existsSync(traceFile)) return res.status(404).json({ error: "Trace not found for session" });
  return res.json(JSON.parse(fs.readFileSync(traceFile, "utf-8")));
});

// ── GET /api/trace/latest ─────────────────────────────────
// Return the most recently written trace file (convenience for post-flow export)
router.get("/trace/latest", (req: Request, res: Response) => {
  const traceDir = path.join(__dirname, "../../data/agent_traces");
  if (!fs.existsSync(traceDir)) return res.status(404).json({ error: "No traces directory" });
  const files = fs.readdirSync(traceDir).filter((f) => f.endsWith(".json"));
  if (!files.length) return res.status(404).json({ error: "No trace files found" });
  const latest = files
    .map((f) => ({ f, mtime: fs.statSync(path.join(traceDir, f)).mtimeMs }))
    .sort((a, b) => b.mtime - a.mtime)[0];
  return res.json(JSON.parse(fs.readFileSync(path.join(traceDir, latest.f), "utf-8")));
});

// ── GET /api/trace/:thread_id ─────────────────────────────
// Export full agent trace for a negotiation — submission artifact
router.get("/trace/:thread_id", (req: Request, res: Response) => {
  const thread = getThread(req.params.thread_id);
  if (!thread) return res.status(404).json({ error: "Thread not found" });
  return res.json({ thread, exported_at: new Date().toISOString() });
});

// ── POST /api/booking/simulate-step ───────────────────────────
router.post("/booking/simulate-step", (req: Request, res: Response) => {
  const { booking_id } = req.body;
  if (!booking_id) return res.status(400).json({ error: "booking_id required" });

  try {
    const booking = getBooking(booking_id);
    if (!booking) return res.status(404).json({ error: "Booking not found" });

    // Only run GPS simulation for bookings actively in transit
    if (booking.status !== "ACCEPTED" && booking.status !== "ARRIVING") {
      return res.json({ status: "skipped", booking });
    }

    // GPS Step Fraction = 0.75 (75% per step — reaches customer in ~4 steps)
    const step_fraction = 0.75;
    const customerLat = booking.customer_lat || 33.6938;
    const customerLng = booking.customer_lng || 73.0551;
    const currentLat = booking.current_lat || 33.6844;
    const currentLng = booking.current_lng || 73.0479;

    const dLat = customerLat - currentLat;
    const dLng = customerLng - currentLng;

    const nextLat = currentLat + dLat * step_fraction;
    const nextLng = currentLng + dLng * step_fraction;

    // Haversine calculation to get new distance
    const R = 6371;
    const dLatRad = ((customerLat - nextLat) * Math.PI) / 180;
    const dLngRad = ((customerLng - nextLng) * Math.PI) / 180;
    const a =
      Math.sin(dLatRad / 2) * Math.sin(dLatRad / 2) +
      Math.cos((nextLat * Math.PI) / 180) *
        Math.cos((customerLat * Math.PI) / 180) *
        Math.sin(dLngRad / 2) *
        Math.sin(dLngRad / 2);
    const distKm = R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const distMeters = Math.round(distKm * 1000);

    // Update coordinates and distance in memory/JSON
    const bookingsFile = path.join(__dirname, "../../data/mock_bookings.json");
    const bookingsData = JSON.parse(fs.readFileSync(bookingsFile, "utf-8"));
    const bIdx = bookingsData.bookings.findIndex((b: any) => b.booking_id === booking_id);

    if (bIdx !== -1) {
      bookingsData.bookings[bIdx].current_lat = nextLat;
      bookingsData.bookings[bIdx].current_lng = nextLng;
      bookingsData.bookings[bIdx].distance_meters = distMeters;

      // Always write GPS + distance_meters to file before any status transitions
      // so progressAgent reads the correct distance when it fires.
      fs.writeFileSync(bookingsFile, JSON.stringify(bookingsData, null, 2));

      if (distMeters <= 50) {
        updateBookingStatus(booking_id, "ARRIVED");
        updateBookingStatus(booking_id, "IN_PROGRESS");
        pushNotification("CUSTOMER", booking_id, "arrived", "Provider Pohonch Gaya! 📍", `${bookingsData.bookings[bIdx].provider_name} aap ke location par pohonch gaya hai.`);
        pushNotification("PROVIDER", booking_id, "mark_done", "Kaam Poora Ho Gaya? 🛠️", `Agar kaam mukammal ho gaya hai to please complete mark karein.`);
      } else if (booking.status === "ACCEPTED") {
        // First step — transition to ARRIVING now that distance_meters is on disk
        updateBookingStatus(booking_id, "ARRIVING");
      }
    }

    const updatedBooking = bookingsData.bookings[bIdx];
    return res.json({ status: "simulated", booking: updatedBooking });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── POST /api/booking/submit-rating ───────────────────────────
router.post("/booking/submit-rating", (req: Request, res: Response) => {
  const { booking_id, stars } = req.body;
  if (!booking_id || stars === undefined) {
    return res.status(400).json({ error: "booking_id and stars are required" });
  }

  try {
    const booking = submitBookingRating(booking_id, stars, new Date().toISOString());
    return res.json({ status: "rated", booking });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── POST /api/booking/cancel-provider ─────────────────────────
router.post("/booking/cancel-provider", (req: Request, res: Response) => {
  const { booking_id } = req.body;
  if (!booking_id) return res.status(400).json({ error: "booking_id is required" });

  try {
    const booking = handleProviderCancellation(booking_id);
    return res.json({ status: "cancelled", booking });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── POST /api/booking/auto-reassign ──────────────────────────
// Now calls RecoveryAgent — empathetic apology + compensation + A2A re-auction.
// Response shape unchanged so frontend needs no update.
router.post("/booking/auto-reassign", async (req: Request, res: Response) => {
  const { booking_id, language } = req.body;
  if (!booking_id) return res.status(400).json({ error: "booking_id required" });

  try {
    const bookingsFile = path.join(__dirname, "../../data/mock_bookings.json");
    const data = JSON.parse(fs.readFileSync(bookingsFile, "utf-8"));

    // Follow chain to latest active booking (idempotency guard)
    let currentIdx = data.bookings.findIndex((b: any) => b.booking_id === booking_id);
    if (currentIdx === -1) return res.status(404).json({ error: "Booking not found" });
    while (data.bookings[currentIdx].reassigned_to) {
      const nextIdx = data.bookings.findIndex(
        (b: any) => b.booking_id === data.bookings[currentIdx].reassigned_to
      );
      if (nextIdx === -1) break;
      currentIdx = nextIdx;
    }
    const booking = data.bookings[currentIdx];

    // Build full exclusion set from chain
    const allTriedProviders = new Set<string>();
    let chainNode: any = booking;
    while (chainNode) {
      if (chainNode.provider_id) allTriedProviders.add(chainNode.provider_id);
      chainNode = chainNode.reassigned_from
        ? data.bookings.find((b: any) => b.booking_id === chainNode.reassigned_from) ?? null
        : null;
    }
    const excludedProviders = Array.from(allTriedProviders);

    const MAX_ATTEMPTS = 10;
    if (excludedProviders.length >= MAX_ATTEMPTS) {
      return res.json({ status: "no_provider", attempt: excludedProviders.length });
    }

    // Delegate to Recovery Agent
    const { handle } = await import("../agents/recoveryAgent.js");
    const result = await handle(booking.booking_id, excludedProviders, language ?? "roman_urdu");

    if (!result.success || !result.new_booking) {
      return res.json({ status: "no_provider", attempt: result.attempts_used, recovery: result });
    }

    // Link new booking in chain
    data.bookings[currentIdx].reassigned_to = result.new_booking.booking_id;
    fs.writeFileSync(bookingsFile, JSON.stringify(data, null, 2));

    return res.json({
      status: "reassigned",
      booking: result.new_booking,
      attempt: result.attempts_used,
      recovery: {
        apology_message: result.apology_message,
        compensation: result.compensation,
        cause: result.cause,
        contract_id: result.new_contract_id,
      },
    });
  } catch (err: any) {
    console.error("[auto-reassign] error:", err);
    return res.status(500).json({ error: err.message });
  }
});

// ── GET /api/notifications ──────────────────────────────
router.get("/notifications", (req: Request, res: Response) => {
  const { role } = req.query;
  try {
    const list = role ? notificationsQueue.filter(n => n.roleTarget === role) : notificationsQueue;
    return res.json(list);
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── POST /api/notifications/clear ───────────────────────
router.post("/notifications/clear", (req: Request, res: Response) => {
  const { id } = req.body;
  try {
    const idx = notificationsQueue.findIndex(n => n.id === id);
    if (idx !== -1) notificationsQueue.splice(idx, 1);
    return res.json({ status: "cleared" });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── GET /api/bookings ───────────────────────────────────
router.get("/bookings", (req: Request, res: Response) => {
  const { customer_id, provider_id } = req.query;
  try {
    const bookingsFile = path.join(__dirname, "../../data/mock_bookings.json");
    let data: any = { bookings: [] };
    if (fs.existsSync(bookingsFile)) {
      data = JSON.parse(fs.readFileSync(bookingsFile, "utf-8"));
    }

    let list = data.bookings;
    if (customer_id) list = list.filter((b: any) => b.customer_id === customer_id);
    if (provider_id) list = list.filter((b: any) => b.provider_id === provider_id);
    return res.json(list);
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── POST /api/booking/generate-summary ────────────────────────
router.post("/booking/generate-summary", async (req: Request, res: Response) => {
  const { booking_id } = req.body;
  try {
    const booking = getBooking(booking_id);
    if (!booking) return res.status(404).json({ error: "Booking not found" });

    // Calculate duration from state history
    const inProgressEntry = booking.state_history.find((h: any) => h.status === "IN_PROGRESS");
    const completedEntry = booking.state_history.find((h: any) => h.status === "COMPLETED");
    let durationMinutes = 45;
    if (inProgressEntry && completedEntry) {
      durationMinutes = Math.max(
        1,
        Math.round((new Date(completedEntry.timestamp).getTime() - new Date(inProgressEntry.timestamp).getTime()) / 60000)
      );
    }

    const completedItems = booking.checklist.filter((i: any) => i.completed).map((i: any) => i.item);

    const summary = {
      invoice_id: `INV-${booking_id}`,
      booking_id,
      generated_at: new Date().toISOString(),
      service_summary: {
        service_type: booking.service_type,
        provider: booking.provider_name,
        location: booking.location,
        duration_minutes: durationMinutes,
        completed_at: completedEntry?.timestamp ?? new Date().toISOString(),
        checklist_completed: completedItems,
        items_done: completedItems.length,
        items_total: booking.checklist.length,
      },
      cost_breakdown: {
        visit_fee: (booking.price_quote as any)?.visit_fee ?? 0,
        labor: (booking.price_quote as any)?.base_rate ?? booking.final_price,
        parts_estimate: 0,
        total: booking.final_price,
        payment_method: "Cash on Delivery",
      },
      agent_note: "Auto-generated by Haazir AI upon job completion.",
    };

    // Persist to invoices folder
    const invoicesDir = path.join(__dirname, "../../data/invoices");
    if (!fs.existsSync(invoicesDir)) fs.mkdirSync(invoicesDir, { recursive: true });
    fs.writeFileSync(path.join(invoicesDir, `${booking_id}.json`), JSON.stringify(summary, null, 2));

    return res.json({ summary });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── DISPUTE RESOLUTION ─────────────────────────────────────
// POST /api/dispute/raise — customer submits a dispute
router.post("/dispute/raise", async (req: Request, res: Response) => {
  const { booking_id, type, comment } = req.body;
  if (!booking_id || !type) return res.status(400).json({ error: "booking_id and type required" });
  try {
    const dispute = await raiseDispute(booking_id, type, comment ?? "");
    return res.json(dispute);
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// GET /api/dispute/:id — evidence bundle + proposed resolution
router.get("/dispute/:id", (req: Request, res: Response) => {
  try {
    const dispute = getDispute(req.params.id);
    if (!dispute) return res.status(404).json({ error: "Dispute not found" });
    return res.json(dispute);
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// GET /api/disputes?booking_id= — list disputes (optionally filtered)
router.get("/disputes", (req: Request, res: Response) => {
  try {
    const bookingId = req.query.booking_id as string | undefined;
    return res.json(listDisputes(bookingId));
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// POST /api/dispute/:id/respond — accept or reject proposed resolution
router.post("/dispute/:id/respond", async (req: Request, res: Response) => {
  const { party, decision } = req.body;
  if (!party || !decision) return res.status(400).json({ error: "party and decision required" });
  try {
    const dispute = await respondToDispute(req.params.id, party, decision);
    return res.json(dispute);
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── A2A NEGOTIATION ────────────────────────────────────────
// GET /api/negotiation/:contract_id — fetch a signed contract
router.get("/negotiation/:contract_id", (req: Request, res: Response) => {
  try {
    const contract = getContract(req.params.contract_id);
    if (!contract) return res.status(404).json({ error: "Contract not found" });
    return res.json(contract);
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// POST /api/negotiation/:contract_id/event — append lifecycle event to contract log
router.post("/negotiation/:contract_id/event", (req: Request, res: Response) => {
  const { event } = req.body;
  if (!event) return res.status(400).json({ error: "event required" });
  try {
    appendEventToContract(req.params.contract_id, event);
    return res.json({ ok: true });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// ── RELIABILITY ────────────────────────────────────────────
// GET /api/provider/:id/reliability — score + last 10 ledger entries
router.get("/provider/:id/reliability", (req: Request, res: Response) => {
  try {
    const snapshot = getReliabilitySnapshot(req.params.id);
    if (!snapshot) return res.status(404).json({ error: "Provider not found" });
    return res.json(snapshot);
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// POST /api/reliability/event — internal: update EWMA on any lifecycle event
router.post("/reliability/event", (req: Request, res: Response) => {
  const { provider_id, event, booking_id } = req.body;
  if (!provider_id || !event) return res.status(400).json({ error: "provider_id and event required" });
  try {
    const result = applyEvent(provider_id, event, booking_id);
    if (!result) return res.status(404).json({ error: "Provider not found" });
    return res.json(result);
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

export default router;
