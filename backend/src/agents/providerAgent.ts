// Provider Agent — deterministic policy-driven bidder.
// Evaluates a CFP against the provider's negotiation_policy and returns a bid or rejection.
// No Gemini calls here — fully deterministic so latency stays near zero.

export interface CFP {
  job_spec: string;
  service_type: string;
  area: string;          // area only, NOT exact address (privacy)
  complexity: "basic" | "intermediate" | "complex";
  budget_ceiling: number;
  urgency: string;
  preferred_time: string;
}

export interface Bid {
  provider_id: string;
  price: number;
  eta_min: number;
  slot: string;
  confidence: number;
  reliability_snapshot: number;
  accepted: boolean;
  reject_reason?: string;
}

export function evaluateCFP(provider: any, cfp: CFP, distanceKm: number): Bid {
  const policy = provider.negotiation_policy ?? {
    min_acceptable_price: Math.round(provider.charges.base_rate * 0.85),
    surge_appetite: 0.5,
    accepts_urgent: true,
    auto_accept_threshold: Math.round(provider.charges.base_rate * 1.15),
    counter_strategy: "meet_in_middle",
  };

  // Hard rejections
  if (cfp.urgency === "emergency" && !policy.accepts_urgent) {
    return _reject(provider.provider_id, "Provider does not accept urgent jobs", provider);
  }
  if (distanceKm > (provider.max_travel_km ?? policy.max_travel_km ?? 20)) {
    return _reject(provider.provider_id, "Outside max travel radius", provider);
  }
  if (cfp.budget_ceiling > 0 && cfp.budget_ceiling < policy.min_acceptable_price) {
    return _reject(provider.provider_id, "Budget ceiling below minimum acceptable price", provider);
  }

  // Compute bid price
  const baseRate = provider.charges.base_rate;
  const travelCost = Math.round(distanceKm * provider.charges.travel_rate);
  const VISIT_FEE = 150;
  let bidPrice = VISIT_FEE + baseRate * 2 + travelCost;

  // Apply urgency surge based on surge_appetite
  if (cfp.urgency === "emergency" || cfp.urgency === "high") {
    const surgeMultiplier = 1 + policy.surge_appetite * 0.3; // max 30% surge at appetite=1
    bidPrice = Math.round(bidPrice * surgeMultiplier);
  }

  const etaMin = Math.round(distanceKm * 3 + 5); // 3 min/km + 5 min base
  const slot   = _resolveSlot(cfp.preferred_time);

  const confidence = Math.min(
    0.98,
    (provider.reliability_score ?? (provider.on_time_score * 100)) / 100 *
    (1 - (provider.cancellation_risk ?? 0.05))
  );

  return {
    provider_id:          provider.provider_id,
    price:                bidPrice,
    eta_min:              etaMin,
    slot,
    confidence:           Math.round(confidence * 100) / 100,
    reliability_snapshot: provider.reliability_score ?? Math.round((provider.on_time_score ?? 0.85) * 100),
    accepted:             true,
  };
}

export function respondToCounter(provider: any, originalBid: Bid, counterPrice: number): Bid {
  const policy = provider.negotiation_policy ?? {};
  const floor  = policy.min_acceptable_price ?? Math.round(provider.charges.base_rate * 0.85);

  if (counterPrice < floor) {
    return { ...originalBid, accepted: false, reject_reason: "Counter below floor price" };
  }

  const strategy = policy.counter_strategy ?? "meet_in_middle";
  let finalPrice: number;

  if (strategy === "hold") {
    finalPrice = originalBid.price; // won't move
  } else if (strategy === "meet_in_middle") {
    finalPrice = Math.round((originalBid.price + counterPrice) / 2);
  } else {
    // small_concession
    finalPrice = Math.round(originalBid.price - (originalBid.price - counterPrice) * 0.25);
  }

  // If our revised price is still above the customer's counter but we can meet the floor, accept
  if (finalPrice < floor) finalPrice = floor;

  return { ...originalBid, price: finalPrice, accepted: true };
}

function _reject(providerId: string, reason: string, provider: any): Bid {
  return {
    provider_id: providerId,
    price: 0, eta_min: 0, slot: "", confidence: 0,
    reliability_snapshot: provider.reliability_score ?? 0,
    accepted: false,
    reject_reason: reason,
  };
}

function _resolveSlot(preferredTime: string): string {
  const now = new Date();
  const ONE_DAY = 86400000;
  switch ((preferredTime ?? "flexible").toLowerCase().replace(/\s/g, "_")) {
    case "asap":              return new Date(Date.now() + 2 * 3600000).toISOString();
    case "today_morning":     return new Date(now.setHours(10, 0, 0, 0)).toISOString();
    case "today_afternoon":   return new Date(now.setHours(14, 0, 0, 0)).toISOString();
    case "today_evening":     return new Date(now.setHours(18, 0, 0, 0)).toISOString();
    case "tomorrow_morning":  return new Date(new Date(Date.now() + ONE_DAY).setHours(10, 0, 0, 0)).toISOString();
    case "tomorrow_afternoon":return new Date(new Date(Date.now() + ONE_DAY).setHours(14, 0, 0, 0)).toISOString();
    default:                  return new Date(new Date(Date.now() + ONE_DAY).setHours(10, 0, 0, 0)).toISOString();
  }
}
