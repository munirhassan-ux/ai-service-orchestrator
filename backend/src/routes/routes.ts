import { Router, Request, Response } from "express";
import { runOrchestration, confirmBookingAfterNegotiation, rerouteToNextProvider, triggerWarmRestart } from "../orchestrator.js";
import { providerRespond, customerRespond, acceptMidpoint, declineMidpoint, getThread } from "../agents/negotiationAgent.js";
import { updateBookingStatus, completeChecklistItem, getBooking, submitBookingRating, handleProviderCancellation } from "../agents/bookingSimulator.js";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
import { processDispute } from "../agents/disputeAgent.js";
import { createSession, getSession, updateSession } from "../session.js";
import { logTraceEvent } from "../trace.js";
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

// ── POST /api/orchestrate ──────────────────────────────────
// Main entry: takes user text, runs full pipeline
router.post("/orchestrate", async (req: Request, res: Response) => {
  const { input, customer_id, job_count, history, session_id } = req.body;
  if (!input && !session_id) return res.status(400).json({ error: "input or session_id required" });

  const customerId = customer_id || "customer_001";
  const userJobCount = job_count || 0;

  try {
    const result = await runOrchestration(input || "", customerId, userJobCount, history || [], session_id);
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
router.post("/booking/status", (req: Request, res: Response) => {
  const { booking_id, status } = req.body;
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

    return res.json({ status: "dispute_logged", result });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
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

    // Transition status to ARRIVING if it is ACCEPTED or PENDING_PROVIDER
    if (booking.status === "ACCEPTED" || booking.status === "PENDING_PROVIDER") {
      updateBookingStatus(booking_id, "ARRIVING");
    }

    // GPS Step Fraction = 0.1 (10%)
    const step_fraction = 0.1;
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

      if (distMeters <= 50) {
        bookingsData.bookings[bIdx].status = "ARRIVED";
        // Also transition to IN_PROGRESS right after for simulation
        bookingsData.bookings[bIdx].state_history.push({ status: "ARRIVED", timestamp: new Date().toISOString() });
        pushNotification("CUSTOMER", booking_id, "arrived", "Provider Pohonch Gaya! 📍", `${bookingsData.bookings[bIdx].provider_name} aap ke location par pohonch gaya hai.`);
        
        bookingsData.bookings[bIdx].status = "IN_PROGRESS";
        bookingsData.bookings[bIdx].state_history.push({ status: "IN_PROGRESS", timestamp: new Date().toISOString() });
        pushNotification("PROVIDER", booking_id, "mark_done", "Kaam Poora Ho Gaya? 🛠️", `Agar kaam mukammal ho gaya hai to please complete mark karein.`);
      }

      fs.writeFileSync(bookingsFile, JSON.stringify(bookingsData, null, 2));
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
    let data = { bookings: [] };
    if (fs.existsSync(bookingsFile)) {
      data = JSON.parse(fs.readFileSync(bookingsFile, "utf-8"));
    }
    let list = data.bookings;
    if (customer_id) {
      list = list.filter((b: any) => b.customer_id === customer_id);
    }
    if (provider_id) {
      list = list.filter((b: any) => b.provider_id === provider_id);
    }
    return res.json(list);
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

export default router;
