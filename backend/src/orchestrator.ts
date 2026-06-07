import { parseIntent, ParsedIntent } from "./agents/intentParser.js";
import { matchProviders, MatchResult, RankedProvider } from "./agents/providerMatcher.js";
import { calculatePrice, PriceQuote } from "./agents/pricingEngine.js";
import { createBooking, getBooking, setCancellationShield } from "./agents/bookingSimulator.js";
import { getSession, updateSession, createSession, appendPrivacyLog, CustomerSession } from "./session.js";
import { logTraceEvent } from "./trace.js";
import { logAction, logFallback, logNegotiation, logBookingCreated, logPhase, logGuardrail } from "./logger.js";
import { redact } from "./middleware/guardrail.js";
import { runNegotiation, linkBookingToContract } from "./agents/negotiationEngine.js";
import { geocodeLocation } from "./agents/providerMatcher.js";
import { loadPreferences, updatePreferences, buildPersonalizedGreeting } from "./agents/preferenceEngine.js";
import { recordStrike, isCustomerBlocked, getBanExpiryMessage } from "./agents/abuseTracker.js";
import { launchProviderApp } from "./utils/providerAppLauncher.js";

export interface AgentTraceStep {
  step: number;
  agent: string;
  phase?: string;
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
  booking_reason?: string;
  reassignment_log?: string[];
  negotiation_trace?: any;
  contract_id?: string;
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

  // ── Block before doing anything else ─────────────────────────────────────
  // 1. Permanently banned customer (10+ cumulative strikes across all sessions)
  if (isCustomerBlocked(customerId)) {
    const banMsg = getBanExpiryMessage(customerId);
    return {
      success: false, session_id: session.session_id, phase: "account_suspended",
      message: `Aap ne platform policies baar baar violate ki hain. ${banMsg} Is ke baad dobara koshish karein.`,
      intent: null, match_result: null, price_quote: null,
      negotiation_thread_id: null, booking: null, trace: [],
    };
  }
  // 2. Session locked after 3 in-session strikes (even for clean messages)
  const sessionStrikes = (session as any).safety_strikes ?? 0;
  if (sessionStrikes >= 3) {
    return {
      success: false, session_id: session.session_id, phase: "session_blocked",
      message: "Aap ka session block ho gaya hai. Naya session shuru karne ke liye refresh karein — lekin dobara policy ki khilaf warzi par account suspend ho ga.",
      intent: null, match_result: null, price_quote: null,
      negotiation_thread_id: null, booking: null, trace: [],
    };
  }

  const rawInput = userInput.trim();
  logPhase(session.session_id, session.phase, rawInput ? `"${rawInput.slice(0, 40)}"` : "empty input");

  // ── 0. GUARDRAIL — PII redaction + safety check ──────────────────────
  const guardrailResult = redact(rawInput);
  if (guardrailResult.redactions.length > 0) {
    appendPrivacyLog(session.session_id, guardrailResult.redactions);
  }
  logGuardrail(guardrailResult.redactions, guardrailResult.safety);
  trace.push({
    step: 0, agent: "Guardrail", phase: "guardrail",
    input: { raw_length: rawInput.length },
    output: {
      redactions: guardrailResult.redactions.map(r => ({ type: r.type, token: r.token })),
      safety: guardrailResult.safety,
      pii_sent_to_llm: false,
    },
    duration_ms: 0,
  });

  if (guardrailResult.safety.flagged) {
    const safetyStrikes = (session as any).safety_strikes ?? 0;
    updateSession(session.session_id, { safety_strikes: safetyStrikes + 1 } as any);
    // Persist strike against the customer across all sessions
    recordStrike(customerId);
    const currentStrike = safetyStrikes + 1;
    const serviceChips = ["AC Repair", "Plumber", "Electrician", "Cleaning", "Carpenter"];

    // 3rd strike — 24-hr ban applied
    if (currentStrike >= 3) {
      return {
        success: false, session_id: session.session_id, phase: "session_blocked",
        message: "Aap ne baar baar esi language use ki hai. Aap ka account 24 ghante ke liye block kar diya gaya hai.",
        intent: null, match_result: null, price_quote: null,
        negotiation_thread_id: null, booking: null, trace,
      };
    }
    const warningMessages = [
      "Yeh zabaan Haazir par allowed nahi. Please respectfully baat karein.",
      "Haazir ek respectful platform hai. Ek aur violation par aap ka account 24 ghante ke liye block ho jayega.",
    ];
    const warnMsg = warningMessages[currentStrike - 1];
    return {
      success: false, session_id: session.session_id, phase: "safety_warning",
      message: warnMsg,
      chips: serviceChips,
      intent: null, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
    };
  }

  // Strip placeholder tokens so Gemini never sees a hint that PII was shared
  const cleanInput = guardrailResult.text
    .replace(/\[(PHONE|EMAIL|CNIC|ADDRESS)_\d+\]/g, '')
    .replace(/\s{2,}/g, ' ')
    .trim();

  // Redact PII from every history entry so prior turns never leak to Gemini
  const cleanHistory = history.map(h => ({
    ...h,
    content: redact(String(h.content ?? '')).text
      .replace(/\[(PHONE|EMAIL|CNIC|ADDRESS)_\d+\]/g, '')
      .trim(),
  }));
  console.log(`[Orchestrator] Session: ${session.session_id} | Phase: ${session.phase} | Input: "${cleanInput}"`);

  // ── 1. GREETING & INTAKE PHASE ─────────────────────────────────────
  if (session.phase === "greeting" || session.phase === "intake") {
    if (!cleanInput) {
      updateSession(session.session_id, { phase: "intake" });
      // Personalize greeting for returning customers
      const prefs = loadPreferences(customerId);
      const personalHint = prefs && prefs.total_bookings > 0
        ? buildPersonalizedGreeting(prefs)
        : "";
      const greeting = prefs && prefs.total_bookings > 0
        ? `Assalam o Alaikum! Haazir mein dobara khush aamdeed! ${personalHint} Aaj kya kaam karwana hai?`
        : "Assalam o Alaikum! Main Haazir AI hoon. Aaj kya kaam karwana hai aap ko?";
      return {
        success: true, session_id: session.session_id, phase: "intake",
        message: greeting,
        chips: ["AC Repair", "Plumber", "Electrician", "Cleaning", "Carpenter", "Other"],
        intent: null, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
      };
    }

    step++;
    const tStart = Date.now();
    let intent: ParsedIntent;
    try {
      intent = await parseIntent(cleanInput, cleanHistory);

      // Merge with previously established fields from the session — never lose what the user already told us
      const prev = session.parsed_intent;
      if (prev) {
        if (!intent.service_type || intent.service_type === "unknown") intent.service_type = prev.service_type;
        if (!intent.problem_description) intent.problem_description = prev.problem_description;
        if (!intent.location || intent.location === "unknown") intent.location = prev.location;
        if (!intent.time_explicitly_provided) {
          intent.time_explicitly_provided = prev.time_explicitly_provided ?? false;
          if (prev.time_explicitly_provided) intent.preferred_time = prev.preferred_time;
        }
        // If all four required fields are now satisfied, clear clarification flag
        const allPresent =
          intent.service_type && intent.service_type !== "unknown" &&
          intent.problem_description &&
          intent.location && intent.location !== "unknown" &&
          intent.time_explicitly_provided;
        if (allPresent) {
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
      trace.push({
        step, agent: "IntentParser",
        input: { user_input: cleanInput },
        output: { error: (err as any)?.message ?? "parse_failed", confidence: 0 },
        duration_ms: Date.now() - tStart,
      });
      return {
        success: false, session_id: session.session_id, phase: "intake",
        message: "Maazrat, samajh nahi aaya. Dobara likhein?",
        intent: null, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
      };
    }

    // Gate: all four required fields must be collected before proceeding to matching
    const missingFields = [
      !intent.service_type || intent.service_type === "unknown" ? "service_type" : "",
      !intent.problem_description ? "problem_description" : "",
      !intent.location || intent.location === "unknown" ? "location" : "",
      !intent.time_explicitly_provided ? "time" : "",
    ].filter(Boolean);

    if (intent.clarification_needed || intent.confidence < 0.75 || missingFields.length > 0) {
      updateSession(session.session_id, { parsed_intent: intent, phase: "intake" });
      const q = intent.clarification_question ||
        (intent.language === "roman_urdu"
          ? "Thori aur details chahiye — kya masla hai, kahan hain aur kab chahiye?"
          : "Could you share what the issue is, your location, and when you need the service?");
      logFallback("IntentParser", `Missing fields: ${missingFields.join(", ")} | confidence=${Math.round(intent.confidence * 100)}%`, q);
      logTraceEvent(session.session_id, {
        agent: "IntentParser",
        fallback_triggered: true,
        reason: `missing_fields=[${missingFields.join(",")}], confidence=${Math.round(intent.confidence * 100)}%, clarification_needed=${intent.clarification_needed}`,
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
  if (session.phase === "thinking") {
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
          ? "Hum maazrat chahte hain. Is waqt aap ke area mein mazeed koi provider available nahi hai. Hum aap ko waitlist par shamil kar rahe hain. 📞 Call: 0300-HAAZIR."
          : "We apologize. No further providers are available in your area at the moment. We are adding you to our waitlist. 📞 Support: 0300-HAAZIR.",
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

    const isUrdu = intent.language !== "english";
    const budgetLabel = intent.budget_sensitivity === "low" ? "Price-Sensitive"
      : intent.budget_sensitivity === "flexible" ? "Flexible Budget"
        : "Standard Budget";

    // ── A2A Negotiation — Customer Agent auctions against top 5 Provider Agents ──
    const userCoords = await geocodeLocation(intent.location);
    const negotiationResult = await runNegotiation(
      providersWithQuotes,
      intent,
      customerId,
      userCoords.lat,
      userCoords.lng
    );

    logNegotiation(negotiationResult.trace, negotiationResult.contract);
    step++;
    trace.push({
      step, agent: "NegotiationEngine",
      input: { candidates: providersWithQuotes.length },
      output: negotiationResult.trace,
      duration_ms: 0,
    });

    // Fall back to top-ranked if negotiation finds no deal (e.g. all providers out of budget)
    const topProvider = negotiationResult.contract
      ? providersWithQuotes.find(p => p.provider_id === negotiationResult.contract!.provider_id)!
        ?? providersWithQuotes[0]
      : providersWithQuotes[0];

    const finalPrice = negotiationResult.contract?.agreed_price ?? topProvider.price_quote!.total;

    const { booking } = await createBooking(
      intent,
      topProvider,
      topProvider.price_quote!,
      finalPrice,
      null,
      customerId,
      session.session_id
    );

    logBookingCreated(booking);
    // Persist customer preferences for future session personalization
    try { updatePreferences(customerId, booking); } catch { /* non-fatal */ }

    // ── Cancellation prediction + silent backup briefing ─────────────────
    // If selected provider has cancellation_risk > 25%, pre-brief next-best as backup
    try {
      const cancellationRisk = topProvider.cancellation_risk ?? 0;
      if (cancellationRisk > 0.25 && providersWithQuotes.length > 1) {
        const backup = providersWithQuotes.find(p => p.provider_id !== topProvider.provider_id);
        if (backup) {
          setCancellationShield(booking.booking_id, backup.provider_id, backup.name);
          console.log(`[CancellationShield] ${topProvider.name} risk=${Math.round(cancellationRisk * 100)}% — backup briefed: ${backup.name}`);
        }
      }
    } catch { /* non-fatal */ }

    // Auto-launch a dedicated provider app instance for this booking
    launchProviderApp(topProvider.name, booking.booking_id).catch(err =>
      console.warn("[Orchestrator] launchProviderApp error:", err?.message)
    );

    // Link booking back to the signed contract
    if (negotiationResult.contract) {
      linkBookingToContract(negotiationResult.contract.contract_id, booking.booking_id);
    }

    const booking_reason = negotiationResult.contract
      ? `A2A auction: ${negotiationResult.trace.proposals.length} bids received in ${negotiationResult.trace.rounds} round(s). ${topProvider.name} won at Rs.${finalPrice}. ${negotiationResult.trace.customer_agent_reasoning}`
      : `${topProvider.name} selected — ${topProvider.distance_km}km away, ${topProvider.rating}★ rating, reliability ${topProvider.reliability_score ?? Math.round(topProvider.on_time_score * 100)}/100.`;

    const reassignmentSteps: string[] = excludedIds.length > 0 ? [
      `⚠️ Previous provider cancelled — excluded from pool`,
      `🔍 Re-running ProviderMatcher (${excludedIds.length} provider${excludedIds.length > 1 ? "s" : ""} excluded)`,
      `✅ Next best match: ${topProvider.name}`,
      `📍 ${topProvider.distance_km}km away, rated ${topProvider.rating}/5 stars`,
      `🤖 Auto-booking ${topProvider.name}...`,
    ] : [];

    const thinkingSteps = reassignmentSteps.length > 0 ? [
      ...reassignmentSteps,
      `Booking confirmed!`,
    ] : [
      `Haazir Engine is searching...`,
      `Extracted: ${intent.service_type} in ${intent.location}`,
      `Priority: ${intent.urgency?.toUpperCase() || "STANDARD"} | Budget: ${budgetLabel}`,
      `Matched ${providersWithQuotes.length} certified professionals`,
      `Score recalculation complete — ranked by 8 weighted factors`,
      `Auto-selecting top match: ${topProvider.name}`,
      `Booking confirmed!`,
    ];

    logPhase(session.session_id, "booking_confirmed", `booking ${booking.booking_id}`);
    logAction(session.session_id, "thinking", "booking_confirmed", {
      provider: topProvider.name,
      booking: booking.booking_id,
      price: `Rs. ${booking.final_price}`,
    }, Date.now() - tStart);
    session = updateSession(session.session_id, {
      matched_providers: providersWithQuotes,
      providers_tried: updatedTried,
      phase: "booking_confirmed",
      current_provider_index: 0,
      price_quote: topProvider.price_quote,
      active_booking_id: booking.booking_id,
    });

    return {
      success: true, session_id: session.session_id, phase: "booking_confirmed",
      message: isUrdu
        ? `Haazir AI ne aap ke liye best provider book kar diya hai!\n\nBooking ID: ${booking.booking_id}\nProvider: ${booking.provider_name}\nScheduled: ${new Date(booking.scheduled_time).toLocaleString("en-PK")}\nTotal: Rs. ${booking.final_price}\n\nAb provider ki confirmation ka intezaar karein. Confirm hone par tracking start ho gi! 🙏`
        : `Haazir AI automatically booked the best provider for you!\n\nBooking ID: ${booking.booking_id}\nProvider: ${booking.provider_name}\nScheduled: ${new Date(booking.scheduled_time).toLocaleString("en-PK")}\nTotal: Rs. ${booking.final_price}\n\nWaiting for provider confirmation. Tracking will start once confirmed! 🙏`,
      chips: [],
      thinking_steps: thinkingSteps,
      intent,
      match_result: {
        top_providers: providersWithQuotes,
        reasoning: matchResult.reasoning,
        fallback_used: matchResult.fallback_used,
        fallback_reason: matchResult.fallback_reason,
        matching_trace: matchResult.matching_trace,
      },
      price_quote: topProvider.price_quote,
      negotiation_thread_id: null,
      booking,
      trace,
      booking_reason,
      reassignment_log: reassignmentSteps.length > 0 ? reassignmentSteps : undefined,
      negotiation_trace: negotiationResult?.trace,
      contract_id: negotiationResult?.contract?.contract_id,
    };
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
    return runOrchestration(cleanInput, customerId, userJobCount, cleanHistory, session.session_id);
  }

  return {
    success: true, session_id: session.session_id, phase: session.phase,
    message: "Assalam o Alaikum! Main Haazir AI hoon. Kya kaam karwana hai?",
    chips: ["AC Repair", "Plumber", "Electrician"],
    intent: null, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
  };
}

export async function triggerWarmRestart(session: CustomerSession, trace: AgentTraceStep[]): Promise<OrchestrationResult> {
  const nextIndex = session.current_provider_index + 1;
  if (session.restart_count >= 2 || nextIndex >= session.matched_providers.length) {
    logFallback("WarmRestart", `No more providers (restart_count=${session.restart_count}, nextIndex=${nextIndex})`, "Returning helpline message");
    updateSession(session.session_id, { phase: "intake" });
    return {
      success: false, session_id: session.session_id, phase: "intake",
      message: `Maazrat, is waqt koi mazeed provider available nahi hai.\n📞 Helpline: 0300-HAAZIR`,
      intent: session.parsed_intent, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
      error: "no_more_providers_available",
    };
  }

  session = updateSession(session.session_id, { current_provider_index: nextIndex, restart_count: session.restart_count + 1, phase: "quoting", negotiation_round: 1 });
  return runOrchestration("", session.customer_id, 0, [], session.session_id);
}

export async function confirmBookingAfterNegotiation(intent: ParsedIntent, provider: RankedProvider, priceQuote: PriceQuote, finalPrice: number, negotiationThreadId: string | null = null, customerId: string = "customer_001"): Promise<{ booking: any; trace: AgentTraceStep[] }> {
  const { booking } = await createBooking(intent, provider, priceQuote, finalPrice, negotiationThreadId, customerId);
  return { booking, trace: [] };
}

export async function rerouteToNextProvider(intent: ParsedIntent, matchResult: MatchResult, failedProviderId: string, userJobCount: number = 0): Promise<OrchestrationResult> {
  const failedIndex = matchResult.top_providers.findIndex(p => p.provider_id === failedProviderId);
  const nextProvider = matchResult.top_providers[failedIndex + 1];
  if (!nextProvider) {
    return { success: false, session_id: "", phase: "intake", message: "No more providers", intent, match_result: matchResult, price_quote: null, negotiation_thread_id: null, booking: null, trace: [] };
  }
  const priceQuote = calculatePrice(intent, nextProvider, matchResult.top_providers, userJobCount);
  return { success: true, session_id: "", phase: "negotiating", message: `Moving to next provider: ${nextProvider.name}`, chips: ["Select " + nextProvider.provider_id], intent, match_result: matchResult, price_quote: priceQuote, negotiation_thread_id: null, booking: null, trace: [] };
}
