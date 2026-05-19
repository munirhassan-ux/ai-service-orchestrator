import { parseIntent } from "./agents/intentParser.js";
import { matchProviders } from "./agents/providerMatcher.js";
import { calculatePrice } from "./agents/pricingEngine.js";
import { createBooking, updateBookingStatus, getBooking } from "./agents/bookingSimulator.js";
import { getSession, updateSession, createSession } from "./session.js";
import { logTraceEvent } from "./trace.js";
export async function runOrchestration(userInput, customerId = "customer_001", userJobCount = 0, history = [], sessionId) {
    const trace = [];
    let step = 0;
    let session;
    if (sessionId) {
        const existing = getSession(sessionId);
        session = existing ?? createSession(customerId);
    }
    else {
        session = createSession(customerId);
    }
    const cleanInput = userInput.trim();
    console.log(`[Orchestrator] Session: ${session.session_id} | Phase: ${session.phase} | Input: "${cleanInput}"`);
    // ── 1. GREETING & INTAKE PHASE ─────────────────────────────────────
    if (session.phase === "greeting" || session.phase === "intake") {
        if (!cleanInput) {
            updateSession(session.session_id, { phase: "intake" });
            return {
                success: true, session_id: session.session_id, phase: "intake",
                message: "Assalam o Alaikum! Main Khedmatgar AI hoon. Aaj kya kaam karwana hai aap ko?",
                chips: ["AC Repair", "Plumber", "Electrician", "Cleaning", "Carpenter", "Other"],
                intent: null, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
            };
        }
        step++;
        const tStart = Date.now();
        let intent;
        try {
            intent = await parseIntent(cleanInput, history);
            trace.push({
                step, agent: "IntentParser",
                input: { user_input: cleanInput },
                output: intent,
                duration_ms: Date.now() - tStart,
                reasoning: intent.reasoning,
            });
            logTraceEvent(session.session_id, { step, agent: "IntentParser", confidence: intent.confidence, input: cleanInput, output: intent });
        }
        catch (err) {
            return {
                success: false, session_id: session.session_id, phase: "intake",
                message: "Maazrat, samajh nahi aaya. Dobara likhein?",
                intent: null, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
            };
        }
        // Check confidence & completeness (Step 1 requirement)
        // If confidence < 0.75, ask exactly one clarifying question matching user's language
        if (intent.clarification_needed || intent.confidence < 0.75 || !intent.service_type || !intent.location) {
            updateSession(session.session_id, { parsed_intent: intent, phase: "intake" });
            const q = intent.clarification_question ||
                (intent.language === "roman_urdu"
                    ? "Aap ki exact location kya hai aur kab kaam karwana hai?"
                    : "Could you please specify your exact location and preferred time?");
            const chips = !intent.service_type ? ["AC Repair", "Plumber", "Electrician", "Cleaning", "Carpenter"] : undefined;
            return {
                success: false, session_id: session.session_id, phase: "intake",
                message: q,
                chips,
                intent, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
            };
        }
        session = updateSession(session.session_id, { parsed_intent: intent, phase: "thinking" });
    }
    // ── 2. MATCHING & THREAD INIT PHASE ─────────────────────────────────
    if (session.phase === "thinking" || (session.phase === "negotiating" && cleanInput.toLowerCase().includes("options"))) {
        step++;
        const tStart = Date.now();
        const intent = session.parsed_intent;
        // Pagination/offset logic for "more options"
        let excludedIds = session.providers_tried || [];
        if (cleanInput.toLowerCase().includes("options") || cleanInput.toLowerCase().includes("doosra")) {
            console.log(`[Orchestrator] Fetching more options, excluding:`, excludedIds);
        }
        else {
            // fresh start
            excludedIds = [];
            updateSession(session.session_id, { providers_tried: [] });
        }
        let matchResult;
        try {
            matchResult = await matchProviders(intent, excludedIds);
            trace.push({
                step, agent: "ProviderMatcher",
                input: { service: intent.service_type, location: intent.location, excluded: excludedIds },
                output: { found: matchResult.top_providers.length },
                duration_ms: Date.now() - tStart,
            });
            logTraceEvent(session.session_id, { step, agent: "ProviderMatcher", output: matchResult });
        }
        catch (err) {
            return {
                success: false, session_id: session.session_id, phase: "intake",
                message: "Matching engine error. Please try again.",
                intent, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
            };
        }
        // Handle no more providers available
        if (matchResult.top_providers.length === 0) {
            updateSession(session.session_id, { phase: "intake" });
            return {
                success: false, session_id: session.session_id, phase: "intake",
                message: intent.language === "roman_urdu"
                    ? "Hum maazrat chahte hain. Is waqt aap ke area mein mazeed koi provider available nahi hai. Hum aap ko waitlist par shamil kar rahe hain. 📞 Call: 0300-KHEDMAT."
                    : "We apologize. No further providers are available in your area at the moment. We are adding you to our waitlist. 📞 Support: 0300-KHEDMAT.",
                intent, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
            };
        }
        // Attach price quote calculations to each provider card
        const providersWithQuotes = matchResult.top_providers.map((p) => {
            const q = calculatePrice(intent, p, matchResult.top_providers, userJobCount);
            return {
                ...p,
                price_quote: q,
            };
        });
        // Update list of tried provider IDs
        const newlyShownIds = matchResult.top_providers.map((p) => p.provider_id);
        const updatedTried = [...excludedIds, ...newlyShownIds];
        session = updateSession(session.session_id, {
            matched_providers: providersWithQuotes,
            providers_tried: updatedTried,
            phase: "negotiating",
            current_provider_index: 0,
            price_quote: providersWithQuotes[0].price_quote,
        });
        const isUrdu = intent.language !== "english";
        const countdown = intent.urgency === "high" ? 180 : intent.urgency === "medium" ? 420 : 900;
        const thinkingSteps = [
            `🤖 Khedmatgar Engine is searching...`,
            `✓ Extraction: ${intent.service_type} in ${intent.location}`,
            `✓ Priority Level: ${intent.urgency?.toUpperCase() || "STANDARD"}`,
            `✓ Matched ${providersWithQuotes.length} certified professionals`,
            `✓ Score recalculation complete!`,
        ];
        return {
            success: true, session_id: session.session_id, phase: "negotiating",
            message: isUrdu
                ? `✅ Khedmatgar AI ne top match dhoond liye hain!\nNeeche diye gaye options mein se kisi ek ko select karein ya mazeed options ke liye 'More Options' tap karein.`
                : `✅ Khedmatgar AI found the best matching professionals!\nSelect one of the providers below, or tap 'More Options' to see others.`,
            chips: ["More Options", "✗ Cancel"],
            thinking_steps: thinkingSteps,
            countdown_seconds: countdown,
            intent,
            match_result: {
                top_providers: providersWithQuotes,
                reasoning: matchResult.reasoning,
                fallback_used: matchResult.fallback_used,
                fallback_reason: matchResult.fallback_reason,
                matching_trace: matchResult.matching_trace,
            },
            price_quote: providersWithQuotes[0].price_quote,
            negotiation_thread_id: null,
            booking: null,
            trace,
        };
    }
    // ── 3. PROVIDER SELECTION SELECTION PHASE ──────────────────────────
    if (session.phase === "negotiating") {
        // If they typed something else or tapped a select button
        const selectMatch = cleanInput.match(/✓ Select\s+(\w+)/i) || cleanInput.match(/Select\s+(\w+)/i);
        if (selectMatch) {
            const selectedId = selectMatch[1];
            const provider = session.matched_providers.find((p) => p.provider_id === selectedId || p.provider_id.toLowerCase() === selectedId.toLowerCase());
            if (!provider) {
                return {
                    success: false, session_id: session.session_id, phase: "negotiating",
                    message: "Invalid provider selected. Please choose from the list.",
                    intent: session.parsed_intent, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
                };
            }
            // Generate the JOB DETAIL object with status = PENDING_PROVIDER
            const { booking } = createBooking(session.parsed_intent, provider, provider.price_quote, provider.price_quote.total, null, customerId);
            session = updateSession(session.session_id, {
                phase: "equipment_ack", // Wait for customer equipment acknowledgment
                active_booking_id: booking.booking_id,
            });
            const isUrdu = session.parsed_intent?.language !== "english";
            return {
                success: true, session_id: session.session_id, phase: "equipment_ack",
                message: isUrdu
                    ? `ℹ️ *Zaroori Maloomat (Equipment/Materials)*:\n\nYeh quote sirf labor charges ke liye hai. Agar kaam mein koi pipeline, screw, wire ya parts istemal hote hain tou un ka cost shamil nahi hai.\n\nKya aap is se agree karte hain?`
                    : `ℹ️ *Important Information (Equipment/Materials)*:\n\nThis quote covers labor only. Any parts, wires, pipes or replacements are NOT included in the estimated total.\n\nDo you understand and agree?`,
                chips: ["✓ Haan, Agree!", "✗ Cancel Booking"],
                intent: session.parsed_intent,
                match_result: null,
                price_quote: provider.price_quote,
                negotiation_thread_id: null,
                booking,
                trace,
            };
        }
        if (cleanInput.toLowerCase().includes("cancel") || cleanInput.startsWith("✗")) {
            updateSession(session.session_id, { phase: "intake" });
            return {
                success: true, session_id: session.session_id, phase: "intake",
                message: "Request cancelled. Aap jab chahein naya request start kar sakte hain! 🙏",
                chips: ["AC Repair", "Plumber", "Electrician"],
                intent: null, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
            };
        }
    }
    // ── 4. EQUIPMENT ACKNOWLEDGEMENT PHASE ──────────────────────────────
    if (session.phase === "equipment_ack") {
        const isUrdu = session.parsed_intent?.language !== "english";
        const bookingId = session.active_booking_id;
        if (cleanInput.toLowerCase().includes("agree") || cleanInput.includes("Haan") || cleanInput.includes("✓")) {
            // Transition state to ACCEPTED (simulated or real provider flow)
            // For immediate confirmation demo, let's mark it as ACCEPTED!
            const booking = updateBookingStatus(bookingId, "ACCEPTED");
            updateSession(session.session_id, { phase: "booking_confirmed" });
            return {
                success: true, session_id: session.session_id, phase: "booking_confirmed",
                message: isUrdu
                    ? `🎉 Mubarak ho! Aap ki booking confirm ho gayi hai.\n\nBooking ID: ${booking.booking_id}\nProvider Name: ${booking.provider_name}\nScheduled Time: ${new Date(booking.scheduled_time).toLocaleString("en-PK")}\nTotal: Rs. ${booking.final_price}\n\nKaam shuru hone par aap ko real-time reminder aur map updates milein ge! 🙏`
                    : `🎉 Congratulations! Your booking is successfully confirmed.\n\nBooking ID: ${booking.booking_id}\nProvider Name: ${booking.provider_name}\nScheduled Time: ${new Date(booking.scheduled_time).toLocaleString("en-PK")}\nTotal: Rs. ${booking.final_price}\n\nYou will receive a reminder 1 hour before arrival with live updates! 🙏`,
                chips: ["Status Check", "New Request"],
                intent: session.parsed_intent,
                match_result: null,
                price_quote: booking.price_quote,
                negotiation_thread_id: null,
                booking,
                trace,
            };
        }
        else {
            // cancel
            updateBookingStatus(bookingId, "CANCELLED_CUSTOMER");
            updateSession(session.session_id, { phase: "intake" });
            return {
                success: true, session_id: session.session_id, phase: "intake",
                message: "Booking cancelled. Naya request likhein...",
                chips: ["AC Repair", "Plumber"],
                intent: null, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
            };
        }
    }
    // ── 5. BOOKING CONFIRMED ACTIONS ────────────────────────────────────
    if (session.phase === "booking_confirmed") {
        if (cleanInput.toLowerCase().includes("status")) {
            const booking = getBooking(session.active_booking_id);
            return {
                success: true, session_id: session.session_id, phase: "booking_confirmed",
                message: `Current Booking Status: ${booking?.status || "UNKNOWN"}\nLocation: ${booking?.location}\nTotal PKR: ${booking?.final_price}`,
                chips: ["Status Check", "New Request"],
                intent: session.parsed_intent, match_result: null, price_quote: null, negotiation_thread_id: null, booking, trace,
            };
        }
        // Reset to start new booking
        session = updateSession(session.session_id, {
            phase: "intake", parsed_intent: null, matched_providers: [], current_provider_index: 0,
            price_quote: null, negotiation_thread_id: null, equipment_acknowledged: false,
            restart_count: 0, negotiation_round: 1, budget_floor_warned: false, active_booking_id: null,
        });
        return runOrchestration(cleanInput, customerId, userJobCount, history, session.session_id);
    }
    return {
        success: true, session_id: session.session_id, phase: session.phase,
        message: "Assalam o Alaikum! Main Khedmatgar AI hoon. Kya kaam karwana hai?",
        chips: ["AC Repair", "Plumber", "Electrician"],
        intent: null, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
    };
}
export async function triggerWarmRestart(session, trace) {
    const nextIndex = session.current_provider_index + 1;
    const failedProvider = session.matched_providers[session.current_provider_index];
    if (session.restart_count >= 2 || nextIndex >= session.matched_providers.length) {
        updateSession(session.session_id, { phase: "intake" });
        return {
            success: false, session_id: session.session_id, phase: "intake",
            message: `Maazrat, is waqt koi mazeed provider available nahi hai.\n📞 Helpline: 0300-KHEDMAT`,
            intent: session.parsed_intent, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
            error: "no_more_providers_available",
        };
    }
    session = updateSession(session.session_id, { current_provider_index: nextIndex, restart_count: session.restart_count + 1, phase: "quoting", negotiation_round: 1 });
    return runOrchestration("", session.customer_id, 0, [], session.session_id);
}
export async function confirmBookingAfterNegotiation(intent, provider, priceQuote, finalPrice, negotiationThreadId = null, customerId = "customer_001") {
    const { booking } = createBooking(intent, provider, priceQuote, finalPrice, negotiationThreadId, customerId);
    return { booking, trace: [] };
}
export async function rerouteToNextProvider(intent, matchResult, failedProviderId, customerId = "customer_001", userJobCount = 0) {
    const failedIndex = matchResult.top_providers.findIndex(p => p.provider_id === failedProviderId);
    const nextProvider = matchResult.top_providers[failedIndex + 1];
    if (!nextProvider) {
        return { success: false, session_id: "", phase: "intake", message: "No more providers", intent, match_result: matchResult, price_quote: null, negotiation_thread_id: null, booking: null, trace: [] };
    }
    const priceQuote = calculatePrice(intent, nextProvider, matchResult.top_providers, userJobCount);
    return { success: true, session_id: "", phase: "negotiating", message: `Moving to next provider: ${nextProvider.name}`, chips: ["Select " + nextProvider.provider_id], intent, match_result: matchResult, price_quote: priceQuote, negotiation_thread_id: null, booking: null, trace: [] };
}
//# sourceMappingURL=orchestrator.js.map