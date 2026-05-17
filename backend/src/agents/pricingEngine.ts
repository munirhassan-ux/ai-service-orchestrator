import { ParsedIntent } from "./intentParser.js";
import { RankedProvider } from "./providerMatcher.js";

export interface PriceQuote {
  base_rate: number;
  distance_fee: number;
  urgency_surcharge: number;
  complexity_premium: number;
  loyalty_discount: number;
  surge_multiplier: number;
  surge_active: boolean;
  visit_fee: number;
  hours_min: number;
  hours_max: number;
  min_total: number;
  max_total: number;
  total: number; // backward compat = max_total
  // Negotiation Round 1: recalculated at minimum provider rate
  min_rate_total: number;
  // Negotiation Round 2: absolute floor (industry standard min)
  floor_min: number;
  floor_max: number;
  // Industry standard for comparison
  industry_standard_min: number;
  industry_standard_max: number;
  currency: "PKR";
  budget_alternative?: {
    provider_id: string;
    provider_name: string;
    min_total: number;
    max_total: number;
    total: number;
    distance_km: number;
    rating: number;
  };
  breakdown_text: string;
  fairness_note: string;
}

// Industry standard rates per service type (PKR)
const INDUSTRY_STANDARDS: Record<string, { min: number; max: number; min_rate: number }> = {
  plumber:      { min: 800,  max: 2000, min_rate: 600 },
  electrician:  { min: 1000, max: 2500, min_rate: 700 },
  ac_repair:    { min: 1500, max: 4000, min_rate: 1200 },
  cleaning:     { min: 1500, max: 3000, min_rate: 1200 },
  carpenter:    { min: 1000, max: 3000, min_rate: 800 },
  painter:      { min: 5000, max: 15000, min_rate: 4000 },
  default:      { min: 800,  max: 2500, min_rate: 600 },
};

export function calculatePrice(
  intent: ParsedIntent,
  provider: RankedProvider,
  allProviders: RankedProvider[],
  userJobCount: number = 0
): PriceQuote {
  const roundToNearest10 = (n: number) => Math.round(n / 10) * 10;

  const visit_fee = 200;
  const hours_min = 1.5;
  const hours_max = 2.0;

  // Base rate from provider
  const base_rate = roundToNearest10(provider.price_per_hour);
  const minimum_price_per_hour = roundToNearest10(base_rate * 0.8);

  // Distance fee: Rs. 20 per km over 3km
  const distance_fee = provider.distance_km > 3
    ? roundToNearest10((provider.distance_km - 3) * 20)
    : 0;

  // Urgency surcharge
  const urgency_surcharge =
    intent.urgency === "high" ? 200 :
    intent.urgency === "medium" ? 100 : 0;

  // Complexity premium
  const complexity_premium =
    intent.job_complexity_hint === "complex" ? 200 :
    intent.job_complexity_hint === "intermediate" ? 150 : 0;

  const loyalty_discount = 0;

  // Surge: if fewer than 2 available providers, apply 1.2x
  const availableCount = allProviders.filter((p) => p.available).length;
  const surge_active = availableCount < 2;
  const surge_multiplier = surge_active ? 1.2 : 1.0;

  const extras = distance_fee + urgency_surcharge + complexity_premium;

  const min_labour = minimum_price_per_hour * hours_min;
  const max_labour = base_rate * hours_max;

  const min_total = roundToNearest10((visit_fee + min_labour + extras) * surge_multiplier);
  const max_total = roundToNearest10((visit_fee + max_labour + extras) * surge_multiplier);

  // ── Round 1 Quote: at provider's minimum rate ─────────────────────────
  const min_rate_total = roundToNearest10(
    (visit_fee + minimum_price_per_hour * hours_min + extras) * surge_multiplier
  );

  // ── Industry Standard for comparison ──────────────────────────────────
  const serviceKey = intent.service_type?.toLowerCase().replace(/\s+/g, "_") || "default";
  const std = INDUSTRY_STANDARDS[serviceKey] || INDUSTRY_STANDARDS["default"];
  const industry_standard_min = std.min;
  const industry_standard_max = std.max;

  // ── Floor (Round 2 = industry standard minimum) ───────────────────────
  const floor_min = roundToNearest10(visit_fee + std.min_rate * hours_min);
  const floor_max = roundToNearest10(visit_fee + std.min_rate * hours_max);

  // ── Budget Alternative ────────────────────────────────────────────────
  const budgetAlt = intent.budget_sensitivity
    ? [...allProviders]
        .filter((p) => p.id !== provider.id && p.available)
        .sort((a, b) => a.price_per_hour - b.price_per_hour)[0]
    : undefined;

  let budgetAltQuote: PriceQuote["budget_alternative"] | undefined;
  if (budgetAlt) {
    const altBase = roundToNearest10(budgetAlt.price_per_hour);
    const altMinBase = roundToNearest10(altBase * 0.8);
    const altDist = budgetAlt.distance_km > 3
      ? roundToNearest10((budgetAlt.distance_km - 3) * 20)
      : 0;
    const altExtras = altDist + urgency_surcharge + complexity_premium;
    const altMin = roundToNearest10((visit_fee + altMinBase * hours_min + altExtras) * surge_multiplier);
    const altMax = roundToNearest10((visit_fee + altBase * hours_max + altExtras) * surge_multiplier);
    budgetAltQuote = {
      provider_id: budgetAlt.id,
      provider_name: budgetAlt.name,
      min_total: altMin,
      max_total: altMax,
      total: altMax,
      distance_km: budgetAlt.distance_km,
      rating: budgetAlt.rating,
    };
  }

  const breakdown_text = [
    `Visit fee: Rs. ${visit_fee}`,
    `Labour: Rs. ${minimum_price_per_hour}-${base_rate}/hr × ${hours_min}–${hours_max} hrs`,
    distance_fee > 0 ? `Distance (${provider.distance_km}km): Rs. ${distance_fee}` : null,
    urgency_surcharge > 0 ? `Urgency: Rs. ${urgency_surcharge}` : null,
    complexity_premium > 0 ? `Complexity (${intent.job_complexity_hint}): Rs. ${complexity_premium}` : null,
    surge_active ? `Surge (×${surge_multiplier}): applied` : null,
    `─────────────────────────────`,
    `Estimated total: Rs. ${min_total} – Rs. ${max_total}`,
  ].filter(Boolean).join("\n");

  const fairness_note = surge_active
    ? "High demand in your area. Price includes a small surge."
    : "Standard market rate for this service.";

  console.log(`[PricingEngine] ${provider.name} | Range: Rs. ${min_total}-${max_total} | Industry Std: Rs. ${industry_standard_min}-${industry_standard_max} | Floor: Rs. ${floor_min}-${floor_max}`);

  return {
    base_rate,
    distance_fee,
    urgency_surcharge,
    complexity_premium,
    loyalty_discount,
    surge_multiplier,
    surge_active,
    visit_fee,
    hours_min,
    hours_max,
    min_total,
    max_total,
    total: max_total,
    min_rate_total,
    floor_min,
    floor_max,
    industry_standard_min,
    industry_standard_max,
    currency: "PKR",
    budget_alternative: budgetAltQuote,
    breakdown_text,
    fairness_note,
  };
}
