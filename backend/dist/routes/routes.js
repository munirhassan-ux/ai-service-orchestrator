import { Router } from "express";
import { runOrchestration, confirmBookingAfterNegotiation, rerouteToNextProvider, triggerWarmRestart } from "../orchestrator.js";
import { providerRespond, customerRespond, acceptMidpoint, declineMidpoint, getThread } from "../agents/negotiationAgent.js";
import { updateBookingStatus, completeChecklistItem, getBooking } from "../agents/bookingSimulator.js";
import { processDispute } from "../agents/disputeAgent.js";
import { createSession, getSession, updateSession } from "../session.js";
import { logTraceEvent } from "../trace.js";
const router = Router();
// ── SESSION MANAGEMENT ─────────────────────────────────────
router.post("/session/create", (req, res) => {
    const { customer_id } = req.body;
    try {
        const session = createSession(customer_id || "customer_001");
        return res.json(session);
    }
    catch (err) {
        return res.status(500).json({ error: err.message });
    }
});
router.get("/session/:id", (req, res) => {
    try {
        const session = getSession(req.params.id);
        if (!session)
            return res.status(404).json({ error: "Session not found" });
        return res.json(session);
    }
    catch (err) {
        return res.status(500).json({ error: err.message });
    }
});
router.patch("/session/:id", (req, res) => {
    try {
        const session = updateSession(req.params.id, req.body);
        return res.json(session);
    }
    catch (err) {
        return res.status(500).json({ error: err.message });
    }
});
// ── POST /api/orchestrate ──────────────────────────────────
// Main entry: takes user text, runs full pipeline
router.post("/orchestrate", async (req, res) => {
    const { input, customer_id, job_count, history, session_id } = req.body;
    if (!input && !session_id)
        return res.status(400).json({ error: "input or session_id required" });
    const customerId = customer_id || "customer_001";
    const userJobCount = job_count || 0;
    try {
        const result = await runOrchestration(input || "", customerId, userJobCount, history || [], session_id);
        return res.json(result);
    }
    catch (err) {
        console.error("[API] /orchestrate error:", err);
        return res.status(500).json({ error: err.message });
    }
});
// ── POST /api/negotiate/timeout ───────────────────────────
// Trigger simulated provider timeout and automatically move to next provider
router.post("/negotiate/timeout", async (req, res) => {
    const { session_id } = req.body;
    if (!session_id)
        return res.status(400).json({ error: "session_id is required" });
    try {
        const session = getSession(session_id);
        if (!session)
            return res.status(404).json({ error: "Session not found" });
        const failedProvider = session.matched_providers[session.current_provider_index];
        logTraceEvent(session_id, {
            agent: "Orchestrator",
            provider_timeout: { provider_id: failedProvider.id, timeout_seconds: 30 },
            gemini_decision: `Simulated timeout triggered for provider ${failedProvider.name}`
        });
        const result = await triggerWarmRestart(session, []);
        return res.json(result);
    }
    catch (err) {
        console.error("[API] /negotiate/timeout error:", err);
        return res.status(500).json({ error: err.message });
    }
});
// ── POST /api/negotiate/provider ──────────────────────────
// Provider: accept | decline | counter
router.post("/negotiate/provider", async (req, res) => {
    const { thread_id, action, counter_price, reason } = req.body;
    if (!thread_id || !action)
        return res.status(400).json({ error: "thread_id and action required" });
    try {
        const thread = await providerRespond(thread_id, action, counter_price, reason);
        return res.json({ status: "ok", thread });
    }
    catch (err) {
        return res.status(500).json({ error: err.message });
    }
});
// ── POST /api/negotiate/customer ──────────────────────────
// Customer: accept | decline | counter
router.post("/negotiate/customer", async (req, res) => {
    const { thread_id, action, counter_price } = req.body;
    if (!thread_id || !action)
        return res.status(400).json({ error: "thread_id and action required" });
    try {
        let thread = await customerRespond(thread_id, action, counter_price);
        // AUTO-SIMULATION: If customer countered, let the provider (AI) respond immediately
        if (action === "counter" && thread.status === "pending_provider") {
            const lastPrice = thread.messages[thread.messages.length - 1].offered_price;
            // AI Provider logic: If price is within 15% of AI quote, accept it!
            const diff = Math.abs(lastPrice - thread.ai_quote) / thread.ai_quote;
            if (diff <= 0.15) {
                thread = await providerRespond(thread_id, "accept");
            }
            else {
                thread = await providerRespond(thread_id, "counter", Math.round(thread.ai_quote * 0.95));
            }
        }
        return res.json({ status: "ok", thread });
    }
    catch (err) {
        return res.status(500).json({ error: err.message });
    }
});
// ── POST /api/negotiate/accept-midpoint ───────────────────
router.post("/negotiate/accept-midpoint", async (req, res) => {
    const { thread_id, accepted_by } = req.body;
    try {
        const thread = acceptMidpoint(thread_id, accepted_by);
        // If both agreed, trigger booking
        if (thread.status === "agreed" && thread.final_price) {
            return res.json({ status: "agreed", final_price: thread.final_price, thread });
        }
        return res.json({ status: "awaiting_other_party", thread });
    }
    catch (err) {
        return res.status(500).json({ error: err.message });
    }
});
// ── POST /api/negotiate/decline-midpoint ──────────────────
router.post("/negotiate/decline-midpoint", async (req, res) => {
    const { thread_id, declined_by, intent, match_result } = req.body;
    if (!thread_id || !declined_by)
        return res.status(400).json({ error: "thread_id and declined_by required" });
    try {
        const thread = declineMidpoint(thread_id, declined_by);
        // Automatic rerouting if intent and match_result are provided
        if (intent && match_result) {
            const result = await rerouteToNextProvider(intent, match_result, thread.provider_id);
            return res.json({ status: "rerouted", result });
        }
        return res.json({ status: "abandoned", thread });
    }
    catch (err) {
        return res.status(500).json({ error: err.message });
    }
});
// ── GET /api/negotiate/:thread_id ─────────────────────────
router.get("/negotiate/:thread_id", (req, res) => {
    const thread = getThread(req.params.thread_id);
    if (!thread)
        return res.status(404).json({ error: "Thread not found" });
    return res.json(thread);
});
// ── POST /api/booking/confirm ─────────────────────────────
// Called after negotiation agrees — creates the actual booking
router.post("/booking/confirm", async (req, res) => {
    const { intent, provider, price_quote, final_price, negotiation_thread_id, customer_id } = req.body;
    try {
        const { booking, trace } = await confirmBookingAfterNegotiation(intent, provider, price_quote, final_price, negotiation_thread_id, customer_id);
        return res.json({ status: "confirmed", booking, trace });
    }
    catch (err) {
        return res.status(500).json({ error: err.message });
    }
});
// ── POST /api/booking/status ──────────────────────────────
router.post("/booking/status", (req, res) => {
    const { booking_id, status } = req.body;
    try {
        const booking = updateBookingStatus(booking_id, status);
        return res.json({ status: "updated", booking });
    }
    catch (err) {
        return res.status(500).json({ error: err.message });
    }
});
// ── POST /api/booking/checklist ───────────────────────────
router.post("/booking/checklist", (req, res) => {
    const { booking_id, item_index } = req.body;
    try {
        const booking = completeChecklistItem(booking_id, item_index);
        return res.json({ status: "updated", booking });
    }
    catch (err) {
        return res.status(500).json({ error: err.message });
    }
});
// ── GET /api/booking/:id ──────────────────────────────────
router.get("/booking/:id", (req, res) => {
    const booking = getBooking(req.params.id);
    if (!booking)
        return res.status(404).json({ error: "Booking not found" });
    return res.json(booking);
});
// ── POST /api/dispute ─────────────────────────────────────
router.post("/dispute", async (req, res) => {
    const { booking_id, provider_id, issue_type, comment } = req.body;
    if (!booking_id || !provider_id || !issue_type) {
        return res.status(400).json({ error: "booking_id, provider_id, and issue_type required" });
    }
    try {
        const result = await processDispute(booking_id, provider_id, issue_type, comment || "");
        // Also mark the booking as disputed
        updateBookingStatus(booking_id, "disputed");
        return res.json({ status: "dispute_logged", result });
    }
    catch (err) {
        return res.status(500).json({ error: err.message });
    }
});
// ── GET /api/trace/:thread_id ─────────────────────────────
// Export full agent trace for a negotiation — submission artifact
router.get("/trace/:thread_id", (req, res) => {
    const thread = getThread(req.params.thread_id);
    if (!thread)
        return res.status(404).json({ error: "Thread not found" });
    return res.json({ thread, exported_at: new Date().toISOString() });
});
export default router;
//# sourceMappingURL=routes.js.map