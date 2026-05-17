export type DisputeType = "quality_complaint" | "price_dispute" | "no_show" | "cancellation";
export interface DisputeResult {
    dispute_id: string;
    booking_id: string;
    provider_id: string;
    issue_type: DisputeType;
    resolution: string;
    provider_impact: {
        new_risk_score: number;
        new_cancellation_rate: number;
        blacklisted: boolean;
    };
    reasoning: string;
}
export declare function processDispute(bookingId: string, providerId: string, issueType: DisputeType, customerComment: string): Promise<DisputeResult>;
//# sourceMappingURL=disputeAgent.d.ts.map