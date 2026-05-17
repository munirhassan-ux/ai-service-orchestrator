export interface ParsedIntent {
    service_type: string;
    service_raw: string;
    location: string;
    urgency: "low" | "medium" | "high";
    preferred_time: string;
    budget_sensitivity: boolean;
    job_complexity_hint: "basic" | "intermediate" | "complex";
    language: "english" | "urdu" | "roman_urdu" | "mixed";
    confidence: number;
    clarification_needed: boolean;
    clarification_question: string | null;
    reasoning: string;
}
export declare function parseIntent(userInput: string, history?: any[]): Promise<ParsedIntent>;
//# sourceMappingURL=intentParser.d.ts.map