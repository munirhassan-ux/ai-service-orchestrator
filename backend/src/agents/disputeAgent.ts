import { GoogleGenerativeAI } from "@google/generative-ai";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const providersFile = path.join(__dirname, "../../data/mock_providers.json");

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

export async function processDispute(
  bookingId: string,
  providerId: string,
  issueType: DisputeType,
  customerComment: string
): Promise<DisputeResult> {
  const genAI = new GoogleGenerativeAI(process.env.GOOGLE_API_KEY!);
  const model = genAI.getGenerativeModel({
    model: "gemini-2.0-flash",
    generationConfig: { responseMimeType: "application/json" }
  });

  // 1. Load provider data
  const providers = JSON.parse(fs.readFileSync(providersFile, "utf-8"));
  const providerIndex = providers.findIndex((p: any) => p.id === providerId);
  if (providerIndex === -1) throw new Error("Provider not found");

  const provider = providers[providerIndex];

  // 2. Use Gemini to determine resolution and reasoning
  const prompt = `You are the Haazir DisputeAgent. A customer has filed a dispute.
  Booking ID: ${bookingId}
  Provider: ${provider.name} (Current Risk: ${provider.risk_score}, Cancel Rate: ${provider.cancellation_rate})
  Issue Type: ${issueType}
  Customer Comment: "${customerComment}"

  Rules:
  - If "no_show", resolution should be "Full refund to customer".
  - If "quality_complaint", resolution could be "Partial refund" or "Free re-service".
  - If "price_dispute", resolution could be "Refund of difference".
  - If "cancellation" (by provider), resolution is "Booking invalidated, provider penalized".

  Return JSON:
  {
    "resolution": "string description",
    "reasoning": "one sentence explanation",
    "risk_penalty": number (0.05 to 0.2),
    "cancel_penalty": number (0.0 to 0.1)
  }`;

  const result = await model.generateContent(prompt);
  const response = await result.response;
  const raw = response.text();
  const geminiResult = JSON.parse(raw.replace(/```json|```/g, "").trim());

  // 3. Update provider stats
  provider.risk_score = Math.min(1.0, provider.risk_score + (geminiResult.risk_penalty || 0.1));
  if (issueType === "cancellation") {
    provider.cancellation_rate = Math.min(1.0, provider.cancellation_rate + (geminiResult.cancel_penalty || 0.05));
  }

  const blacklisted = provider.risk_score > 0.7 || provider.cancellation_rate > 0.3;
  if (blacklisted) {
    provider.available = false;
  }

  providers[providerIndex] = provider;
  fs.writeFileSync(providersFile, JSON.stringify(providers, null, 2));

  return {
    dispute_id: `DIS-${Date.now()}`,
    booking_id: bookingId,
    provider_id: providerId,
    issue_type: issueType,
    resolution: geminiResult.resolution,
    provider_impact: {
      new_risk_score: provider.risk_score,
      new_cancellation_rate: provider.cancellation_rate,
      blacklisted
    },
    reasoning: geminiResult.reasoning
  };
}
