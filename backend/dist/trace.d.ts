export interface TraceEvent {
    step?: number;
    agent?: string;
    model?: string;
    prompt_summary?: string;
    gemini_decision?: string;
    confidence?: number;
    input?: any;
    output?: any;
    duration_ms?: number;
    fallback_triggered?: boolean;
    phase_after?: string;
    [key: string]: any;
}
export declare function logTraceEvent(sessionId: string, event: TraceEvent): void;
//# sourceMappingURL=trace.d.ts.map