import { ParsedIntent } from "./intentParser.js";
import { RankedProvider } from "./providerMatcher.js";
import { logPricing } from "../logger.js";

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
  total: number; 
  min_rate_total: number;
  floor_min: number;
  floor_max: number;
  industry_standard_min: number;
  industry_standard_max: number;
  currency: "PKR";
  breakdown_text: string;
  fairness_note: string;
}

export function calculatePrice(
  intent: ParsedIntent,
  provider: RankedProvider,
  allProviders: RankedProvider[],
  userJobCount: number = 0
): PriceQuote {
  const roundToNearest10 = (n: number) => Math.round(n / 10) * 10;

  // Exact Charge Calculations:
  // travel_distance_km = haversine(provider.lat, provider.lng, customer.lat, customer.lng)
  // travel_charges = travel_distance_km * provider.charges.travel_rate
  // on_demand_charges = service_fee * (0.15 for high / 0.30 for emergency)
  // total = service_fee + travel_charges + on_demand_charges

  // Base rate (PKR per hour)
  const base_rate = provider.charges.base_rate;
  const travel_rate = provider.charges.travel_rate || 30;

  // Let's assume estimated duration of 2 hours for all calculations.
  const estimated_hours = 2.0;
  const service_fee = roundToNearest10(base_rate * estimated_hours);

  // Travel charges
  const travel_distance_km = provider.distance_km;
  const travel_charges = roundToNearest10(travel_distance_km * travel_rate);

  // On demand charges based on urgency
  let on_demand_charges = 0;
  const lowerUrgency = (intent.urgency || "low").toLowerCase();
  if (lowerUrgency === "high" || lowerUrgency === "emergency") {
    const multiplier = lowerUrgency === "emergency" ? 0.30 : 0.15;
    on_demand_charges = roundToNearest10(service_fee * multiplier);
  }

  // Visit fee — non-refundable call-out charge
  const visit_fee = 150;

  // Total calculation
  const total = roundToNearest10(visit_fee + service_fee + travel_charges + on_demand_charges);

  // Ranges for backward-compatibility with UI
  const min_total = roundToNearest10(total * 0.95);
  const max_total = roundToNearest10(total * 1.05);

  const breakdown_text = [
    `Visit Fee (non-refundable): Rs. ${visit_fee}`,
    `Labour (Rs. ${provider.charges.base_rate}/hr × 2hrs): Rs. ${service_fee}`,
    travel_charges > 0 ? `Travel (${provider.distance_km}km): Rs. ${travel_charges}` : null,
    on_demand_charges > 0 ? `Urgency Surcharge: Rs. ${on_demand_charges}` : null,
    `─────────────────────────────`,
    `Total: Rs. ${total}`,
  ].filter(Boolean).join("\n");

  const fairness_note = "Standard flat-rate pricing applied, incorporating travel rate and urgency surge.";

  const quote: PriceQuote = {
    base_rate,
    distance_fee: travel_charges,
    urgency_surcharge: on_demand_charges,
    complexity_premium: 0,
    loyalty_discount: 0,
    surge_multiplier: 1.0,
    surge_active: false,
    visit_fee,
    hours_min: estimated_hours,
    hours_max: estimated_hours,
    min_total,
    max_total,
    total,
    min_rate_total: min_total,
    floor_min: roundToNearest10(total * 0.9),
    floor_max: roundToNearest10(total * 1.1),
    industry_standard_min: roundToNearest10(service_fee * 0.8),
    industry_standard_max: roundToNearest10(service_fee * 1.3),
    currency: "PKR",
    breakdown_text,
    fairness_note,
  };
  logPricing(provider, intent, quote);
  return quote;
}
