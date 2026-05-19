import { ParsedIntent } from "./agents/intentParser.js";
import { MatchResult, RankedProvider } from "./agents/providerMatcher.js";
import { PriceQuote } from "./agents/pricingEngine.js";
import { CustomerSession } from "./session.js";
export interface AgentTraceStep {
    step: number;
    agent: string;
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
}
export declare function runOrchestration(userInput: string, customerId?: string, userJobCount?: number, history?: any[], sessionId?: string): Promise<OrchestrationResult>;
export declare function triggerWarmRestart(session: CustomerSession, trace: AgentTraceStep[]): Promise<OrchestrationResult>;
export declare function confirmBookingAfterNegotiation(intent: ParsedIntent, provider: RankedProvider, priceQuote: PriceQuote, finalPrice: number, negotiationThreadId?: string | null, customerId?: string): Promise<{
    booking: any;
    trace: AgentTraceStep[];
}>;
export declare function rerouteToNextProvider(intent: ParsedIntent, matchResult: MatchResult, failedProviderId: string, customerId?: string, userJobCount?: number): Promise<OrchestrationResult>;
//# sourceMappingURL=orchestrator.d.ts.map