import { parseIntent, ParsedIntent } from "./agents/intentParser.js";
import { matchProviders, MatchResult, RankedProvider } from "./agents/providerMatcher.js";
import { calculatePrice, PriceQuote } from "./agents/pricingEngine.js";
import { createNegotiationThread, customerRespond, providerRespond, getThread } from "./agents/negotiationAgent.js";
import { createBooking } from "./agents/bookingSimulator.js";
import { getSession, updateSession, createSession, CustomerSession } from "./session.js";
import { logTraceEvent } from "./trace.js";
import { GoogleGenerativeAI } from "@google/generative-ai";

export interface AgentTraceStep {
  step: number;
  agent: string;
  input: any;
  output: any;
  duration_ms: number;
  reasoning?: string;
  fallback?: boolean;
}

export interface OrchestrationResult {
  success: boolean;
  session_id: string;
  phase: string;
  message: string;
  chips?: string[]; // quick-reply chips to show
  intent: ParsedIntent | null;
  match_result: MatchResult | null;
  price_quote: PriceQuote | null;
  negotiation_thread_id: string | null;
  booking: any | null;
  trace: AgentTraceStep[];
  error?: string;
  thinking_steps?: string[]; // agent transparency lines
  countdown_seconds?: number; // for provider response window
}

async function parseNegotiationInput(userInput: string, aiQuote: number): Promise<{ action: "accept" | "decline" | "counter"; price?: number }> {
  const lower = userInput.toLowerCase().trim();
  // Fast keyword matching first (avoids API call on obvious cases)
  if (/\b(ok|done|theek|confirm|manzoor|accept|haan|bilkul|zaroor|sahi|chalega)\b/.test(lower)) {
    return { action: "accept" };
  }
  if (/\b(no|nahi|nah|cancel|nhi|reject|band|rehne|choro)\b/.test(lower)) {
    return { action: "decline" };
  }
  const numMatch = userInput.match(/\d{3,6}/);
  if (numMatch) {
    return { action: "counter", price: parseInt(numMatch[0], 10) };
  }
  if (/\b(kam|sasta|thora|cheap|less|discount|aur)\b/.test(lower)) {
    return { action: "counter", price: Math.round((aiQuote * 0.9) / 10) * 10 };
  }
  // Fallback: Gemini parse
  try {
    const genAI = new GoogleGenerativeAI(process.env.GOOGLE_API_KEY!);
    const model = genAI.getGenerativeModel({
      model: "gemini-2.0-flash",
      generationConfig: { responseMimeType: "application/json" },
    });
    const result = await model.generateContent(
      `Pakistani home service negotiation. AI quoted Rs. ${aiQuote}. Customer said: "${userInput}". Classify as accept/decline/counter. If counter, extract PKR price.\nReturn JSON: {"action":"accept"|"decline"|"counter","price":number|null}`
    );
    return JSON.parse(result.response.text().trim());
  } catch {
    return { action: "counter", price: Math.round((aiQuote * 0.9) / 10) * 10 };
  }
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

  console.log(`[Orchestrator] Session: ${session.session_id} | Phase: ${session.phase} | Input: "${userInput}"`);

  // ── PHASE: GREETING / INTAKE ────────────────────────────────────────
  if (session.phase === "greeting" || session.phase === "intake") {
    if (!userInput.trim()) {
      // First open — show greeting with service chips
      updateSession(session.session_id, { phase: "intake" });
      return {
        success: true, session_id: session.session_id, phase: "intake",
        message: "Assalam o Alaikum! Main Khedmatgar AI hoon. Aaj kya kaam karwana hai aap ko?",
        chips: ["AC Repair", "Plumber", "Electrician", "Cleaning", "Carpenter", "Other"],
        intent: null, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
      };
    }

    step++;
    const t = Date.now();
    let intent: ParsedIntent;
    try {
      intent = await parseIntent(userInput, history);
      trace.push({ step, agent: "IntentParser", input: { user_input: userInput }, output: intent, duration_ms: Date.now() - t, reasoning: intent.reasoning });
      logTraceEvent(session.session_id, { step, agent: "IntentParser", model: "gemini-2.0-flash", confidence: intent.confidence, input: userInput, output: intent });
    } catch (err: any) {
      return { success: false, session_id: session.session_id, phase: "intake", message: "Maazrat, samajh nahi aaya. Dobara likhein?", intent: null, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace };
    }

    if (intent.clarification_needed) {
      updateSession(session.session_id, { parsed_intent: intent, phase: "intake" });
      const chips = !intent.service_type ? ["AC Repair", "Plumber", "Electrician", "Cleaning", "Carpenter"] :
                    !intent.preferred_time ? ["Abhi (ASAP)", "Aaj shaam", "Kal subah", "Kal shaam", "Is hafte mein"] : undefined;
      return {
        success: false, session_id: session.session_id, phase: "intake",
        message: intent.clarification_question || "Kuch aur maloomat chahiye.",
        chips,
        intent, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
      };
    }

    session = updateSession(session.session_id, { parsed_intent: intent, phase: "thinking" });
  }

  // ── PHASE: THINKING ─────────────────────────────────────────────────
  if (session.phase === "thinking") {
    step++;
    const t = Date.now();
    const intent = session.parsed_intent!;

    // Budget floor check BEFORE matching
    if (intent.budget_sensitivity && !session.budget_floor_warned) {
      // We'll compute a rough minimum from industry data after matching
      // Flag for now, handle post-match
    }

    let matchResult: MatchResult;
    try {
      matchResult = await matchProviders(intent);
      trace.push({ step, agent: "ProviderMatcher", input: { service: intent.service_type, location: intent.location }, output: { found: matchResult.top_providers.length, top: matchResult.top_providers[0]?.name }, duration_ms: Date.now() - t });
      logTraceEvent(session.session_id, { step, agent: "ProviderMatcher", gemini_decision: `Matched ${matchResult.top_providers.length} providers`, output: matchResult });
    } catch (err: any) {
      return { success: false, session_id: session.session_id, phase: "intake", message: "Provider search failed. Please try again.", intent, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace };
    }

    if (!matchResult.top_providers.length) {
      updateSession(session.session_id, { phase: "intake" });
      return {
        success: false, session_id: session.session_id, phase: "intake",
        message: "Maazrat, aap ki location mein abhi koi provider available nahi hai. Thori der baad try karein.",
        intent, match_result: matchResult, price_quote: null, negotiation_thread_id: null, booking: null, trace,
      };
    }

    session = updateSession(session.session_id, { matched_providers: matchResult.top_providers, current_provider_index: 0, phase: "quoting" });

    const thinkingSteps = [
      `🤖 Theek hai, main kaam shuru karta hoon...`,
      `✓ Samajh liya: ${intent.service_raw || intent.service_type} in ${intent.location}`,
      `✓ Urgency: ${intent.urgency === "high" ? "High 🔴" : intent.urgency === "medium" ? "Medium 🟡" : "Low 🟢"}`,
      `✓ ${matchResult.top_providers.length} eligible providers mile`,
      `✓ Best match: ${matchResult.top_providers[0].name} (Score: ${(matchResult.top_providers[0].score * 100).toFixed(0)}%)`,
      `✓ Quote ready hai!`,
    ];

    // Fall through to quoting
    return await runOrchestration("", customerId, userJobCount, history, session.session_id);
  }

  // ── PHASE: QUOTING ───────────────────────────────────────────────────
  if (session.phase === "quoting") {
    step++;
    const t = Date.now();
    const intent = session.parsed_intent!;
    const provider = session.matched_providers[session.current_provider_index];

    let priceQuote: PriceQuote;
    try {
      priceQuote = calculatePrice(intent, provider, session.matched_providers, userJobCount);
      trace.push({ step, agent: "PricingEngine", input: { provider: provider.name, urgency: intent.urgency }, output: priceQuote, duration_ms: Date.now() - t });
      logTraceEvent(session.session_id, { step, agent: "PricingEngine", output: priceQuote });
    } catch (err: any) {
      return { success: false, session_id: session.session_id, phase: "intake", message: "Pricing error.", intent, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace };
    }

    // Budget floor check
    if (intent.budget_sensitivity && !session.budget_floor_warned) {
      const budgetMatch = userInput.match(/\d{3,6}/);
      if (budgetMatch) {
        const customerBudget = parseInt(budgetMatch[0]);
        if (customerBudget < priceQuote.floor_min) {
          updateSession(session.session_id, { budget_floor_warned: true, price_quote: priceQuote });
          return {
            success: true, session_id: session.session_id, phase: "budget_floor",
            message: `Aap ka budget Rs. ${customerBudget} hai, lekin is area mein ${intent.service_type} ka minimum rate Rs. ${priceQuote.floor_min} hai. Fuel aur visiting charges bhi shamil hain.\n\nKya aap Rs. ${priceQuote.floor_min} tak adjust kar sakte hain?`,
            chips: ["Haan, theek hai", "Nahi, cancel karo"],
            intent, match_result: null, price_quote: priceQuote, negotiation_thread_id: null, booking: null, trace,
          };
        }
      }
    }

    // Create negotiation thread
    let threadId: string;
    try {
      const bookingRequestId = `REQ-${Date.now()}`;
      const thread = createNegotiationThread(bookingRequestId, provider.id, customerId, priceQuote.total, session.session_id, intent.preferred_time);
      threadId = thread.id;
    } catch (err: any) {
      return { success: false, session_id: session.session_id, phase: "quoting", message: "Failed to create negotiation.", intent, match_result: null, price_quote: priceQuote, negotiation_thread_id: null, booking: null, trace };
    }

    session = updateSession(session.session_id, { price_quote: priceQuote, negotiation_thread_id: threadId, phase: "negotiating", negotiation_round: 1 });

    const isUrdu = intent.language !== "english";
    const countdown = intent.urgency === "high" ? 180 : intent.urgency === "medium" ? 420 : 900;

    const thinkingSteps = [
      `🤖 Theek hai, main kaam shuru karta hoon...`,
      `✓ Samajh liya: ${intent.service_raw || intent.service_type} in ${intent.location}`,
      `✓ Problem type: ${intent.job_complexity_hint}`,
      `✓ Urgency: ${intent.urgency === "high" ? "High 🔴" : intent.urgency === "medium" ? "Medium 🟡" : "Low 🟢"}`,
      `✓ ${session.matched_providers.length} eligible providers mile`,
      `✓ Best match: ${provider.name}`,
      `✓ Quote ready hai!`,
    ];

    return {
      success: true, session_id: session.session_id, phase: "negotiating",
      message: isUrdu
        ? `✅ Best match mila!\n👷 ${provider.name}\n⭐ ${provider.rating}★ | 📍 ${provider.distance_km}km door\n\nKya aap yeh quote accept karte hain?`
        : `✅ Best match found!\n👷 ${provider.name}\n⭐ ${provider.rating}★ | 📍 ${provider.distance_km}km away\n\nDo you accept this quote?`,
      chips: ["✓ Accept", "🔽 Thora kam karo", "✗ Cancel"],
      thinking_steps: thinkingSteps,
      countdown_seconds: countdown,
      intent, match_result: { top_providers: session.matched_providers, reasoning: "", fallback_used: false, matching_trace: "" },
      price_quote: priceQuote, negotiation_thread_id: threadId, booking: null, trace,
    };
  }

  // ── PHASE: BUDGET FLOOR RESPONSE ────────────────────────────────────
  if (session.phase === "budget_floor") {
    const lower = userInput.toLowerCase();
    if (lower.includes("nahi") || lower.includes("cancel") || lower.includes("nah")) {
      updateSession(session.session_id, { phase: "intake" });
      return {
        success: true, session_id: session.session_id, phase: "intake",
        message: "Theek hai! Jab chahein wapis aayein. Khedmatgar hamesha available hai. 🙏",
        intent: session.parsed_intent, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
      };
    }
    // Customer agreed to adjust budget — continue to quoting
    session = updateSession(session.session_id, { phase: "quoting", budget_floor_warned: true });
    return runOrchestration("", customerId, userJobCount, history, session.session_id);
  }

  // ── PHASE: NEGOTIATING ───────────────────────────────────────────────
  if (session.phase === "negotiating") {
    step++;
    const threadId = session.negotiation_thread_id!;
    const priceQuote = session.price_quote!;
    const intent = session.parsed_intent!;
    const provider = session.matched_providers[session.current_provider_index];
    const isUrdu = intent.language !== "english";

    const parsedAction = await parseNegotiationInput(userInput, priceQuote.total);
    logTraceEvent(session.session_id, { step, agent: "NegotiationParser", gemini_decision: `${parsedAction.action} @ Rs. ${parsedAction.price || "none"}`, input: userInput, output: parsedAction });

    if (parsedAction.action === "accept" || (userInput.trim().startsWith("✓") && userInput.includes("Accept"))) {
      const thread = await customerRespond(threadId, "accept");
      session = updateSession(session.session_id, { phase: "equipment_ack" });
      const finalPrice = thread.final_price || priceQuote.min_total;
      return {
        success: true, session_id: session.session_id, phase: "equipment_ack",
        message: isUrdu
          ? `ℹ️ Ek zaroori baat confirm karein:\n\nYeh booking sirf LABOUR charges ke liye hai.\nAgar koi part, pipe, fitting, ya koi bhi material lagta hai toh uska cost is quote mein shamil NAHI hai. Provider aap ko on-site pehle batayega aur aap ki permission ke baad hi use karega.\n\nKya aap yeh samajh gaye aur agree karte hain?`
          : `ℹ️ Important: This booking covers LABOUR only.\nAny parts, pipes, or materials are NOT included. The provider will inform you on-site before using anything.\n\nDo you understand and agree?`,
        chips: ["✓ Haan, samajh gaya — Aage barhao"],
        intent, match_result: null, price_quote: priceQuote, negotiation_thread_id: threadId, booking: null, trace,
      };
    }

    if (parsedAction.action === "decline" || userInput.includes("✗ Cancel")) {
      await customerRespond(threadId, "decline");
      return triggerWarmRestart(session, trace);
    }

    // Counter-offer logic with rounds
    const round = session.negotiation_round || 1;
    const offerPrice = parsedAction.price || Math.round((priceQuote.min_total * 0.9) / 10) * 10;

    if (round === 1) {
      // Round 1: Recalculate at minimum rate
      session = updateSession(session.session_id, { negotiation_round: 2 });
      const revisedMin = priceQuote.min_rate_total;
      const revisedMax = priceQuote.min_rate_total + 200; // small range
      return {
        success: true, session_id: session.session_id, phase: "negotiating",
        message: isUrdu
          ? `Samajh gaya. Main minimum rate par recalculate karta hoon...\n💰 Revised Quote (minimum rate):\n\n${priceQuote.breakdown_text}\n─────────────────────────────\nRevised: Rs. ${revisedMin} – Rs. ${revisedMax}\n\nYeh is provider ka minimum rate hai — isse kam par woh available nahi hoga.\nIndustry standard: Rs. ${priceQuote.industry_standard_min} – Rs. ${priceQuote.industry_standard_max}\n\nKya ab theek hai?`
          : `Understood. Recalculating at minimum rate...\n💰 Revised: Rs. ${revisedMin} – Rs. ${revisedMax}\n\nIndustry standard: Rs. ${priceQuote.industry_standard_min} – Rs. ${priceQuote.industry_standard_max}\n\nIs this acceptable?`,
        chips: ["✓ Accept", "🔽 Aur kam?", "✗ Cancel"],
        intent, match_result: null, price_quote: priceQuote, negotiation_thread_id: threadId, booking: null, trace,
      };
    } else if (round === 2) {
      // Round 2: Show industry floor as final offer
      session = updateSession(session.session_id, { negotiation_round: 3 });
      return {
        success: true, session_id: session.session_id, phase: "negotiating",
        message: isUrdu
          ? `Main industry standard bhi check kar raha hoon...\nIs kaam ka Pakistan mein standard rate: Rs. ${priceQuote.industry_standard_min} – Rs. ${priceQuote.industry_standard_max}\n\nIs provider ka minimum already Rs. ${priceQuote.floor_min} hai jo industry standard ke andar hai. Hum isse kam nahi ja sakte.\n\n🔴 Final offer: Rs. ${priceQuote.floor_min} – Rs. ${priceQuote.floor_max}\nIsse kam possible nahi. Accept karte hain?`
          : `Checking industry standard...\nPakistan standard for this service: Rs. ${priceQuote.industry_standard_min} – Rs. ${priceQuote.industry_standard_max}\n\n🔴 Final offer: Rs. ${priceQuote.floor_min} – Rs. ${priceQuote.floor_max}\nThis is the absolute minimum. Accept?`,
        chips: ["✓ Final Accept", "✗ Nahi, doosra provider dhundho"],
        intent, match_result: null, price_quote: priceQuote, negotiation_thread_id: threadId, booking: null, trace,
      };
    } else {
      // Round 3+: Customer still pushing — warm restart with next provider
      return triggerWarmRestart(session, trace);
    }
  }

  // ── PHASE: EQUIPMENT ACK ──────────────────────────────────────────────
  if (session.phase === "equipment_ack") {
    const threadId = session.negotiation_thread_id!;
    const thread = getThread(threadId);
    const finalPrice = thread?.final_price || session.price_quote!.min_rate_total;
    const provider = session.matched_providers[session.current_provider_index];

    logTraceEvent(session.session_id, { step: step + 1, agent: "BookingSimulator", equipment_acknowledged: new Date().toISOString(), gemini_decision: "Equipment ack received. Creating booking." });
    session = updateSession(session.session_id, { equipment_acknowledged: true, phase: "booking_confirmed" });

    const { booking } = createBooking(session.parsed_intent!, provider, session.price_quote!, finalPrice, threadId, customerId);
    updateSession(session.session_id, { active_booking_id: booking.booking_id });

    const isUrdu = session.parsed_intent?.language !== "english";
    return {
      success: true, session_id: session.session_id, phase: "booking_confirmed",
      message: isUrdu
        ? `🎉 Khabar acha hai!\n${provider.name} ne job accept kar li!\n\nBooking ID: ${booking.booking_id}\n1 ghante pehle reminder milega. Shukriya Khedmatgar use karne ka! 🙏`
        : `🎉 Great news!\nBooking confirmed with ${provider.name}!\n\nBooking ID: ${booking.booking_id}\nYou'll get a 1-hour reminder. Thank you for using Khedmatgar! 🙏`,
      intent: session.parsed_intent, match_result: null, price_quote: session.price_quote,
      negotiation_thread_id: threadId, booking, trace,
    };
  }

  // ── PHASE: BOOKING CONFIRMED — new request ────────────────────────────
  if (session.phase === "booking_confirmed") {
    // Customer typed after booking — treat as new request
    session = updateSession(session.session_id, {
      phase: "intake", parsed_intent: null, matched_providers: [], current_provider_index: 0,
      price_quote: null, negotiation_thread_id: null, equipment_acknowledged: false,
      restart_count: 0, negotiation_round: 1, budget_floor_warned: false,
    });
    return runOrchestration(userInput, customerId, userJobCount, history, session.session_id);
  }

  return {
    success: true, session_id: session.session_id, phase: session.phase,
    message: "Assalam o Alaikum! Main Khedmatgar AI hoon. Kya kaam karwana hai?",
    chips: ["AC Repair", "Plumber", "Electrician", "Cleaning", "Carpenter"],
    intent: null, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
  };
}

export async function triggerWarmRestart(session: CustomerSession, trace: AgentTraceStep[]): Promise<OrchestrationResult> {
  const nextIndex = session.current_provider_index + 1;
  const failedProvider = session.matched_providers[session.current_provider_index];

  logTraceEvent(session.session_id, { agent: "Orchestrator", provider_skipped: { provider_id: failedProvider?.id, reason: "Decline or timeout" }, warm_restart: { restart_count: session.restart_count + 1 } });

  if (session.restart_count >= 2 || nextIndex >= session.matched_providers.length) {
    updateSession(session.session_id, { phase: "intake" });
    return {
      success: false, session_id: session.session_id, phase: "intake",
      message: `Hum maazrat chahte hain. Is waqt aap ke requirements ke liye koi provider available nahi hai.\n\n📅 Kal subah try karein\n💰 Budget thora adjust karein\n📞 Humein call karein: 0300-KHEDMAT\n\nNaya request shuru karne ke liye likhein...`,
      intent: session.parsed_intent, match_result: null, price_quote: null, negotiation_thread_id: null, booking: null, trace,
      error: "no_more_providers_available",
    };
  }

  session = updateSession(session.session_id, { current_provider_index: nextIndex, restart_count: session.restart_count + 1, phase: "quoting", negotiation_round: 1 });
  const nextProvider = session.matched_providers[nextIndex];
  console.log(`[Orchestrator] Warm restart: next provider ${nextProvider.name}`);
  return runOrchestration("", session.customer_id, 0, [], session.session_id);
}

export async function confirmBookingAfterNegotiation(intent: ParsedIntent, provider: RankedProvider, priceQuote: PriceQuote, finalPrice: number, negotiationThreadId: string | null = null, customerId: string = "customer_001"): Promise<{ booking: any; trace: AgentTraceStep[] }> {
  const { booking } = createBooking(intent, provider, priceQuote, finalPrice, negotiationThreadId, customerId);
  return { booking, trace: [] };
}

export async function rerouteToNextProvider(intent: ParsedIntent, matchResult: MatchResult, failedProviderId: string, customerId: string = "customer_001", userJobCount: number = 0): Promise<OrchestrationResult> {
  const failedIndex = matchResult.top_providers.findIndex(p => p.id === failedProviderId);
  const nextProvider = matchResult.top_providers[failedIndex + 1];
  if (!nextProvider) {
    return { success: false, session_id: "", phase: "intake", message: "No more providers", intent, match_result: matchResult, price_quote: null, negotiation_thread_id: null, booking: null, trace: [] };
  }
  const priceQuote = calculatePrice(intent, nextProvider, matchResult.top_providers, userJobCount);
  const thread = createNegotiationThread(`REQ-REROUTE-${Date.now()}`, nextProvider.id, customerId, priceQuote.total);
  return { success: true, session_id: "", phase: "negotiating", message: `Moving to next provider: ${nextProvider.name}`, chips: ["✓ Accept", "🔽 Thora kam karo", "✗ Cancel"], intent, match_result: matchResult, price_quote: priceQuote, negotiation_thread_id: thread.id, booking: null, trace: [] };
}
