// Customer Agent — scores incoming bids and decides: ACCEPT directly, COUNTER, or reject all.
// Uses Gemini only for the reasoning text in the trace. All scoring is deterministic.

import { GoogleGenerativeAI } from "@google/generative-ai";
import { Bid } from "./providerAgent.js";

export interface AuctionInput {
  bids: Bid[];
  budget_ceiling: number;
  urgency: string;
  preferred_price?: number; // hint from intent (budget_sensitivity)
  session_language: "roman_urdu" | "urdu" | "english";
}

export interface AuctionDecision {
  action: "accept" | "counter" | "no_deal";
  selected_provider_id?: string;
  accepted_bid?: Bid;
  counter_targets?: Array<{ provider_id: string; counter_price: number }>;
  reasoning: string; // Gemini-generated explanation
}

// Utility score: lower price + higher reliability + faster ETA = higher score
function utilityScore(bid: Bid, budgetCeiling: number): number {
  const priceScore    = budgetCeiling > 0 ? Math.max(0, 1 - bid.price / budgetCeiling) : 0.5;
  const reliabilityScore = bid.reliability_snapshot / 100;
  const etaScore      = Math.max(0, 1 - bid.eta_min / 90); // 90 min = 0 score
  return 0.40 * reliabilityScore + 0.35 * priceScore + 0.25 * etaScore;
}

export async function runAuction(input: AuctionInput): Promise<AuctionDecision> {
  const validBids = input.bids.filter(b => b.accepted);

  if (validBids.length === 0) {
    return { action: "no_deal", reasoning: "No provider agents submitted valid bids." };
  }

  // Sort by utility score descending
  const ranked = validBids
    .map(b => ({ bid: b, utility: utilityScore(b, input.budget_ceiling) }))
    .sort((a, b) => b.utility - a.utility);

  const best = ranked[0].bid;

  // Auto-accept if best bid is within budget or close (budget ≤ 0 means no ceiling)
  const withinBudget = input.budget_ceiling <= 0 || best.price <= input.budget_ceiling;
  // Also accept if provider has auto_accept_threshold logic (handled server-side by provider policy)

  let action: "accept" | "counter" | "no_deal" = "accept";
  let counterTargets: Array<{ provider_id: string; counter_price: number }> | undefined;

  if (!withinBudget) {
    // Counter to top 2 if over budget
    const targets = ranked.slice(0, 2).map(({ bid }) => ({
      provider_id: bid.provider_id,
      counter_price: Math.round(input.budget_ceiling * 0.95), // target just under ceiling
    }));
    action = "counter";
    counterTargets = targets;
  }

  // Generate Gemini reasoning
  const reasoning = await _generateReasoning(best, ranked, input, action);

  return {
    action,
    selected_provider_id: action === "accept" ? best.provider_id : undefined,
    accepted_bid: action === "accept" ? best : undefined,
    counter_targets: counterTargets,
    reasoning,
  };
}

async function _generateReasoning(
  best: Bid,
  ranked: Array<{ bid: Bid; utility: number }>,
  input: AuctionInput,
  action: string
): Promise<string> {
  try {
    const genAI = new GoogleGenerativeAI(process.env.GOOGLE_API_KEY!);
    const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

    const lang = input.session_language === "english" ? "English" : "Roman Urdu / Urdu";
    const bidsSummary = ranked.slice(0, 3).map(({ bid }, i) =>
      `#${i + 1}: Provider ${bid.provider_id} — Rs.${bid.price}, ETA ${bid.eta_min}min, reliability ${bid.reliability_snapshot}`
    ).join("\n");

    const prompt = `You are Haazir's Customer Agent. Write exactly 1 sentence in ${lang} explaining this decision.

Bids received:
${bidsSummary}

Decision: ${action.toUpperCase()} — Selected: ${best.provider_id} at Rs.${best.price}
Budget ceiling: ${input.budget_ceiling > 0 ? "Rs." + input.budget_ceiling : "flexible"}
Urgency: ${input.urgency}

Be specific about why this provider wins (reliability, price, ETA). No markdown.`;

    const response = await model.generateContent(prompt);
    return response.response.text().trim();
  } catch {
    return `${best.provider_id} selected — Rs.${best.price}, ${best.eta_min}min ETA, reliability ${best.reliability_snapshot}/100.`;
  }
}
