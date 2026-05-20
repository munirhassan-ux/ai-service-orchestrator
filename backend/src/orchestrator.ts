import { parseIntent, ParsedIntent } from "./agents/intentParser.js";
import { matchProviders, MatchResult, RankedProvider } from "./agents/providerMatcher.js";
import { calculatePrice, PriceQuote } from "./agents/pricingEngine.js";
import { createBooking, updateBookingStatus, getBooking } from "./agents/bookingSimulator.js";
import { getSession, updateSession, createSession, CustomerSession } from "./session.js";
import { logTraceEvent } from "./trace.js";
import { logAction, logFallback } from "./logger.js";
import { GoogleGenerativeAI } from "@google/generative-ai";

export interface AgentTraceStep {
  step: number;
  agent: string;
  input: any;
  output: any;
  duration_ms: number;
  reasoning?: string;
}

export interface OrchestrationResult {
  success: boolean;
  session_id: string;
  phase: string;
  message: string;
  chips?: string[];
  intent: ParsedIntent | null;
  match_result: MatchResult | null;
  price_quote: PriceQuote | null;
  negotiation_thread_id: string | null;
  booking: any | null;
  trace: AgentTraceStep[];
  error?: string;
  thinking_steps?: string[];
  countdown_seconds?: number;
}

export async function runOrchestration(
  userInput: string,
  customerId: string = "customer_001",
  userJobCount: number = 0,
  history: any[] = [],
  sessionId?: string
): Promise<OrchestrationResult> {
  const trace: AgentTraceStep[] = [];
  let step = 0;

  let session: CustomerSession;
  if (sessionId) {
    const existing = getSession(sessionId);
    session = existing ?? createSession(customerId);
  } else {
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
    let intent: ParsedIntent;
    try {
      intent = await parseIntent(cleanInput, history);

      // Merge with previously established fields from the session — never lose what the user already told us
      const prev = session.parsed_intent;
      if (prev) {
        if (!intent.service_type || intent.service_type === "unknown") intent.service_type = prev.service_type;
        if (!intent.location || intent.location === "unknown") intent.location = prev.location;
        if (!intent.preferred_time || intent.preferred_time === "flexible") intent.preferred_time = prev.preferred_time;
        // If merged fields now satisfy requirements, clear the clarification flag
        if (intent.service_type && intent.service_type !== "unknown" && intent.location && intent.location !== "unknown") {
          intent.clarification_needed = false;
          if (intent.confidence < 0.75) intent.confidence = 0.8;
        }
      }

      trace.push({
        step, agent: "IntentParser",
        input: { user_input: cleanInput },
        output: intent,
        duration_ms: Date.now() - tStart,
        reasoning: intent.reasoning,
      });
      logTraceEvent(session.session_id, { step, agent: "IntentParser", confidence: intent.confidence, input: cleanInput, output: intent });
    } catch (err: any) {
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
      logFallback("IntentParser", `Low confidence (${Math.round(intent.confidence * 100)}%) or missing fields`, q);
      logTraceEvent(session.session_id, {
        agent: "IntentParser",
        fallback_triggered: true,
        reason: `confidence=${Math.round(intent.confidence * 100)}%, clarification_needed=${intent.clarification_needed}, missing_fields=${!intent.service_type ? "service_type " : ""}${!intent.location ? "location" : ""}`.trim(),
        clarification_question: q,
      });
      const chips = !intent.service_type ? ["AC Repair", "Plumber", "Electrician", "Cleaning", "Carpenter"] : undefined;
      return {
        success: false, session_id: session.session_id, phase: "intake",
        message: q,
        chips,
        intent, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
      };
    }

    logAction(session.session_id, session.phase, "thinking", { service: intent.service_type, location: intent.location });
    session = updateSession(session.session_id, { parsed_intent: intent, phase: "thinking" });
  }

  // ── 2. MATCHING & THREAD INIT PHASE ─────────────────────────────────
  if (session.phase === "thinking" || (session.phase === "negotiating" && cleanInput.toLowerCase().includes("options"))) {
    step++;
    const tStart = Date.now();
    const intent = session.parsed_intent!;

    // Pagination/offset logic for "more options"
    let excludedIds = session.providers_tried || [];
    if (cleanInput.toLowerCase().includes("options") || cleanInput.toLowerCase().includes("doosra")) {
      console.log(`[Orchestrator] Fetching more options, excluding:`, excludedIds);
    } else {
      // fresh start
      excludedIds = [];
      updateSession(session.session_id, { providers_tried: [] });
    }

    let matchResult: MatchResult;
    try {
      matchResult = await matchProviders(intent, excludedIds);
      trace.push({
        step, agent: "ProviderMatcher",
        input: { service: intent.service_type, location: intent.location, excluded: excludedIds },
        output: { found: matchResult.top_providers.length },
        duration_ms: Date.now() - tStart,
      });
      logTraceEvent(session.session_id, { step, agent: "ProviderMatcher", output: matchResult });
    } catch (err: any) {
      return {
        success: false, session_id: session.session_id, phase: "intake",
        message: "Matching engine error. Please try again.",
        intent, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
      };
    }

    // Handle no more providers available
    if (matchResult.top_providers.length === 0) {
      logFallback("ProviderMatcher", "No providers matched for service/location", "Returning waitlist message to customer");
      logTraceEvent(session.session_id, {
        agent: "ProviderMatcher",
        fallback_triggered: true,
        reason: "no_providers_matched",
        service_type: intent.service_type,
        location: intent.location,
        excluded_ids: excludedIds,
        phase_after: "waitlisted",
      });
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

    // Mark the cheapest provider for budget-sensitive customers
    if (intent.budget_sensitivity === "low" || intent.budget_sensitivity === "medium") {
      let cheapestIdx = 0;
      for (let i = 1; i < providersWithQuotes.length; i++) {
        if ((providersWithQuotes[i].price_quote as any).total < (providersWithQuotes[cheapestIdx].price_quote as any).total) {
          cheapestIdx = i;
        }
      }
      (providersWithQuotes[cheapestIdx] as any).is_budget_pick = true;
    }

    logTraceEvent(session.session_id, {
      agent: "PricingEngine",
      phase_after: "pricing_complete",
      budget_sensitivity: intent.budget_sensitivity,
      providers_priced: providersWithQuotes.map((p) => ({
        provider_id: p.provider_id,
        name: p.name,
        score: p.score,
        is_budget_pick: !!(p as any).is_budget_pick,
        quote: {
          visit_fee: p.price_quote.visit_fee,
          base_rate: p.price_quote.base_rate,
          distance_fee: p.price_quote.distance_fee,
          urgency_surcharge: p.price_quote.urgency_surcharge,
          total: p.price_quote.total,
          fairness_note: p.price_quote.fairness_note,
        },
      })),
    });

    // Update list of tried provider IDs
    const newlyShownIds = matchResult.top_providers.map((p) => p.provider_id);
    const updatedTried = [...excludedIds, ...newlyShownIds];

    logAction(session.session_id, "thinking", "negotiating", {
      providers: String(providersWithQuotes.length),
      top: providersWithQuotes[0]?.name,
      fallback: matchResult.fallback_used ? matchResult.fallback_reason ?? "yes" : "no",
    }, Date.now() - tStart);
    session = updateSession(session.session_id, {
      matched_providers: providersWithQuotes,
      providers_tried: updatedTried,
      phase: "negotiating",
      current_provider_index: 0,
      price_quote: providersWithQuotes[0].price_quote,
    });

    const isUrdu = intent.language !== "english";
    const countdown = intent.urgency === "high" ? 180 : intent.urgency === "medium" ? 420 : 900;

    const budgetLabel = intent.budget_sensitivity === "low" ? "Price-Sensitive"
      : intent.budget_sensitivity === "flexible" ? "Flexible Budget"
      : "Standard Budget";
    const thinkingSteps = [
      `🤖 Khedmatgar Engine is searching...`,
      `✓ Extracted: ${intent.service_type} in ${intent.location}`,
      `✓ Priority: ${intent.urgency?.toUpperCase() || "STANDARD"} | Budget: ${budgetLabel}`,
      `✓ Matched ${providersWithQuotes.length} certified professionals`,
      `✓ Score recalculation complete — ranked by 8 weighted factors`,
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
      const { booking } = createBooking(
        session.parsed_intent!,
        provider,
        provider.price_quote!,
        provider.price_quote!.total,
        null,
        customerId,
        session.session_id
      );

      logAction(session.session_id, "negotiating", "equipment_ack", {
        provider: provider.name,
        booking: booking.booking_id,
        price: `Rs. ${booking.final_price}`,
      });
      session = updateSession(session.session_id, {
        phase: "equipment_ack",
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
    const bookingId = session.active_booking_id!;

    if (cleanInput.toLowerCase().includes("agree") || cleanInput.includes("Haan") || cleanInput.includes("✓")) {
      // Booking was already created as PENDING_PROVIDER — keep it that way.
      // The provider must explicitly accept before we move to ACCEPTED.
      const booking = getBooking(bookingId);
      if (!booking) throw new Error(`Booking ${bookingId} not found`);

      logAction(session.session_id, "equipment_ack", "booking_confirmed", {
        booking: booking.booking_id,
        status: booking.status,
      });
      updateSession(session.session_id, { phase: "booking_confirmed" });

      return {
        success: true, session_id: session.session_id, phase: "booking_confirmed",
        message: isUrdu
          ? `✅ Shukriya! Aap ki request provider ko bhej di gayi hai.\n\nBooking ID: ${booking.booking_id}\nProvider: ${booking.provider_name}\nScheduled: ${new Date(booking.scheduled_time).toLocaleString("en-PK")}\nTotal: Rs. ${booking.final_price}\n\nAb provider ki confirmation ka intezaar karein. Confirm hone par simulation start ho gi! 🙏`
          : `✅ Thank you! Your request has been sent to the provider.\n\nBooking ID: ${booking.booking_id}\nProvider: ${booking.provider_name}\nScheduled: ${new Date(booking.scheduled_time).toLocaleString("en-PK")}\nTotal: Rs. ${booking.final_price}\n\nWaiting for provider confirmation. Simulation will start once confirmed! 🙏`,
        chips: [],
        intent: session.parsed_intent,
        match_result: null,
        price_quote: booking.price_quote,
        negotiation_thread_id: null,
        booking,
        trace,
      };
    } else {
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
      const booking = getBooking(session.active_booking_id!);
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

export async function triggerWarmRestart(session: CustomerSession, trace: AgentTraceStep[]): Promise<OrchestrationResult> {
  const nextIndex = session.current_provider_index + 1;
  const failedProvider = session.matched_providers[session.current_provider_index];

  if (session.restart_count >= 2 || nextIndex >= session.matched_providers.length) {
    logFallback("WarmRestart", `No more providers (restart_count=${session.restart_count}, nextIndex=${nextIndex})`, "Returning helpline message");
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

export async function confirmBookingAfterNegotiation(intent: ParsedIntent, provider: RankedProvider, priceQuote: PriceQuote, finalPrice: number, negotiationThreadId: string | null = null, customerId: string = "customer_001"): Promise<{ booking: any; trace: AgentTraceStep[] }> {
  const { booking } = createBooking(intent, provider, priceQuote, finalPrice, negotiationThreadId, customerId);
  return { booking, trace: [] };
}

export async function rerouteToNextProvider(intent: ParsedIntent, matchResult: MatchResult, failedProviderId: string, customerId: string = "customer_001", userJobCount: number = 0): Promise<OrchestrationResult> {
  const failedIndex = matchResult.top_providers.findIndex(p => p.provider_id === failedProviderId);
  const nextProvider = matchResult.top_providers[failedIndex + 1];
  if (!nextProvider) {
    return { success: false, session_id: "", phase: "intake", message: "No more providers", intent, match_result: matchResult, price_quote: null, negotiation_thread_id: null, booking: null, trace: [] };
  }
  const priceQuote = calculatePrice(intent, nextProvider, matchResult.top_providers, userJobCount);
  return { success: true, session_id: "", phase: "negotiating", message: `Moving to next provider: ${nextProvider.name}`, chips: ["Select " + nextProvider.provider_id], intent, match_result: matchResult, price_quote: priceQuote, negotiation_thread_id: null, booking: null, trace: [] };
}
