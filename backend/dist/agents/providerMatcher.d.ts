import { ParsedIntent } from "./intentParser.js";
export interface RankedProvider {
    provider_id: string;
    name: string;
    shop_name: string;
    location: {
        latitude: number;
        longitude: number;
    };
    city: string;
    city_area: string;
    availability_status: "online" | "offline";
    charges: {
        base_rate: number;
        travel_rate: number;
    };
    job_role: string;
    service_expertise: string[];
    rating: number;
    on_time_score: number;
    cancellation_risk: number;
    capacity: number;
    active_jobs: number;
    total_reviews: number;
    total_jobs: number;
    distance_km: number;
    score: number;
    score_breakdown: {
        travel_time: number;
        availability_match: number;
        specialization: number;
        on_time: number;
        review_sentiment: number;
        rate: number;
        cancellation_risk: number;
        capacity: number;
    };
    is_waitlisted?: boolean;
    price_quote?: any;
}
export interface MatchResult {
    top_providers: RankedProvider[];
    reasoning: string;
    fallback_used: boolean;
    fallback_reason?: string;
    matching_trace: string;
}
export declare function matchProviders(intent: ParsedIntent, excludedIds?: string[]): Promise<MatchResult>;
//# sourceMappingURL=providerMatcher.d.ts.map