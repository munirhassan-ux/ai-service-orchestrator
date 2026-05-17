import { ParsedIntent } from "./agents/intentParser.js";
import { RankedProvider } from "./agents/providerMatcher.js";
import { PriceQuote } from "./agents/pricingEngine.js";
export interface ProviderProfile {
    name: string;
    services: string[];
    areas: string[];
    rate_per_hour: number;
    min_rate_per_hour: number;
    skill_level: "basic" | "intermediate" | "expert";
}
export interface CustomerSession {
    session_id: string;
    customer_id: string;
    role: "customer" | "provider";
    phase: string;
    parsed_intent: ParsedIntent | null;
    matched_providers: RankedProvider[];
    providers_tried: string[];
    current_provider_index: number;
    price_quote: PriceQuote | null;
    negotiation_thread_id: string | null;
    equipment_acknowledged: boolean;
    restart_count: number;
    agreed_price_range: {
        min: number;
        max: number;
    } | null;
    negotiation_round: number;
    budget_floor_warned: boolean;
    provider_profile: ProviderProfile | null;
    provider_setup_step: number;
    created_at: string;
    updated_at: string;
    expires_at: string;
    active_booking_id: string | null;
}
export declare function generateSessionId(): string;
export declare function createSession(customerId: string, role?: "customer" | "provider"): CustomerSession;
export declare function getSession(sessionId: string): CustomerSession | null;
export declare function updateSession(sessionId: string, updates: Partial<CustomerSession>): CustomerSession;
//# sourceMappingURL=session.d.ts.map