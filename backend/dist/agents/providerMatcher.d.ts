import { ParsedIntent } from "./intentParser.js";
export interface RankedProvider {
    id: string;
    name: string;
    service_types: string[];
    skill_level: string;
    rating: number;
    on_time_score: number;
    cancellation_rate: number;
    risk_score: number;
    price_per_hour: number;
    city_area: string;
    available: boolean;
    distance_km: number;
    score: number;
    score_breakdown: {
        proximity: number;
        rating_recency: number;
        on_time: number;
        skill_match: number;
        price_fit: number;
        availability: number;
    };
    next_available_slot?: string;
}
export interface MatchResult {
    top_providers: RankedProvider[];
    reasoning: string;
    fallback_used: boolean;
    fallback_reason?: string;
    matching_trace: string;
}
export declare function matchProviders(intent: ParsedIntent): Promise<MatchResult>;
//# sourceMappingURL=providerMatcher.d.ts.map