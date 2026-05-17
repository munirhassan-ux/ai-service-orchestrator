export type NegotiationStatus = "pending_provider" | "pending_customer" | "agreed" | "declined" | "abandoned" | "ai_suggested";
export interface NegotiationMessage {
    from: "customer" | "provider" | "ai";
    message: string;
    offered_price: number;
    timestamp: string;
}
export interface NegotiationThread {
    id: string;
    booking_request_id: string;
    provider_id: string;
    customer_id: string;
    session_id?: string;
    ai_quote: number;
    final_price: number | null;
    status: NegotiationStatus;
    round: number;
    max_rounds: number;
    messages: NegotiationMessage[];
    created_at: string;
    updated_at: string;
}
export declare function createNegotiationThread(bookingRequestId: string, providerId: string, customerId: string, aiQuote: number, sessionId?: string, preferredTime?: string): NegotiationThread;
export declare function providerRespond(threadId: string, action: "accept" | "decline" | "counter", counterPrice?: number, reason?: string): Promise<NegotiationThread>;
export declare function customerRespond(threadId: string, action: "accept" | "decline" | "counter", counterPrice?: number): Promise<NegotiationThread>;
export declare function acceptMidpoint(threadId: string, acceptedBy: "customer" | "provider"): NegotiationThread;
export declare function declineMidpoint(threadId: string, declinedBy: "customer" | "provider"): NegotiationThread;
export declare function getThread(threadId: string): NegotiationThread | undefined;
//# sourceMappingURL=negotiationAgent.d.ts.map