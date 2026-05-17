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
    total: number;
    min_rate_total: number;
    floor_min: number;
    floor_max: number;
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
export declare function calculatePrice(intent: ParsedIntent, provider: RankedProvider, allProviders: RankedProvider[], userJobCount?: number): PriceQuote;
//# sourceMappingURL=pricingEngine.d.ts.map