import { GoogleGenerativeAI } from "@google/generative-ai";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { logIntent } from "../logger.js";

const __filename = fileURLToPath(import.meta.url);
const currDir = path.dirname(__filename);

const romanUrduMap = JSON.parse(
  fs.readFileSync(path.join(currDir, "../../data/roman_urdu_map.json"), "utf-8")
);

export interface ParsedIntent {
  service_type: string;
  service_raw: string;
  location: string;
  urgency: "low" | "medium" | "high" | "emergency";
  preferred_time: string;
  budget_sensitivity: "low" | "medium" | "flexible";
  job_complexity_hint: "basic" | "intermediate" | "complex";
  language: "english" | "urdu" | "roman_urdu" | "mixed";
  confidence: number;
  clarification_needed: boolean;
  clarification_question: string | null;
  reasoning: string;
}

const SYSTEM_PROMPT = `You are an intelligent conversational AI agent for Haazir, a Pakistani home services platform.
Users write in English, Urdu, or Roman Urdu. Your goal is to extract service intent and maintain a natural conversation flow.

Extract ONLY valid JSON.

Service types available:
ac_repair, ac_installation, ac_maintenance, plumber, electrician, cleaning, carpenter, painter, geyser_repair, fridge_repair, solar_repair, tiling, etc.

Return this JSON:
{
  "service_type": "string",
  "service_raw": "string",
  "location": "string",
  "urgency": "low|medium|high|emergency",
  "preferred_time": "string",
  "budget_sensitivity": "low|medium|flexible",
  "job_complexity_hint": "basic|intermediate|complex",
  "language": "english|urdu|roman_urdu|mixed",
  "confidence": number,
  "clarification_needed": boolean,
  "clarification_question": "string|null",
  "reasoning": "string"
}

STRICT CONVERSATIONAL RULES:
1. If "location" is missing or too vague (e.g. just "Lahore" without a neighbourhood), set "clarification_needed": true and ask for their specific area.
2. If "service_type" is missing or truly ambiguous, set "clarification_needed": true and ask what they need help with.
3. "preferred_time" is OPTIONAL. If missing, default it to "flexible" and do NOT set "clarification_needed": true because of it.
4. LANGUAGE PARITY: If the user speaks in Roman Urdu, the "clarification_question" MUST be in Roman Urdu.
5. BE POLITE: Use "G bilkul", "Ji", "Sure" etc. in your follow-up questions.
6. If service_type AND location are present, set "clarification_needed": false even if preferred_time is absent.

FUZZY MATCHING — always try to infer before asking:
7. MISSPELLINGS: Correct common misspellings to the nearest service. Examples:
   - "pambr", "plambr", "pambar" → plumber
   - "alectric", "electrition", "elec" → electrician
   - "carpnter", "carpinter" → carpenter
   - "cleenng", "clening" → cleaning
   - "AC repir", "ac ripar", "AC kharab" → ac_repair
8. SYMPTOM-TO-SERVICE MAPPING: If the user describes a problem, infer the service. Examples:
   - "pani nahi aa raha", "pipe se leak", "nala band" → plumber
   - "bijli nahi hai", "lights band", "short circuit", "wire kharab" → electrician
   - "AC thanda nahi karta", "AC band ho gaya", "AC gas khatam" → ac_repair
   - "geyser kaam nahi kar raha", "garam pani nahi" → geyser_repair
   - "fridge thanda nahi karta", "fridge kharab" → fridge_repair
   - "darwaza toot gaya", "furniture fix", "almari" → carpenter
9. MIXED LANGUAGE: Handle English words inside Roman Urdu sentences naturally (e.g. "mujhe kal electrician chahiye G-11 mein").
10. AMBIGUOUS BUT INFERABLE: If the user gives minimal info but enough to infer (e.g. "AC", "plumber", "cleaner"), do NOT ask clarification — assume service matches and just ask for location if missing.
11. Never ask about preferred_time — it is always optional.`;

export async function parseIntent(userInput: string, history: any[] = []): Promise<ParsedIntent> {
  const traceStart = Date.now();

  const historyText = history.map(h => `${h.role}: ${h.content}`).join("\n");

  // Pre-process: check Roman Urdu map for known signals
  const lowerInput = userInput.toLowerCase();
  let detectedService = "";

  for (const [key, value] of Object.entries(romanUrduMap.service_map)) {
    if (lowerInput.includes(key)) {
      detectedService = value as string;
      break;
    }
  }

  const genAI = new GoogleGenerativeAI(process.env.GOOGLE_API_KEY!);
  const model = genAI.getGenerativeModel({
    model: "gemini-3.1-flash-lite",
    systemInstruction: SYSTEM_PROMPT,
    generationConfig: { responseMimeType: "application/json" }
  });

  const result = await model.generateContent(`
    CONVERSATION HISTORY:
    ${historyText}

    NEW USER INPUT: "${userInput}"
    
    ${detectedService ? `\n\nHint: Roman Urdu map suggests service_type = "${detectedService}"` : ""}
  `);

  const response = await result.response;
  const raw = response.text();

  let parsed: ParsedIntent;
  try {
    parsed = JSON.parse(raw.replace(/```json|```/g, "").trim());
  } catch {
    // Fallback if JSON parse fails
    parsed = {
      service_type: detectedService || "unknown",
      service_raw: userInput,
      location: "unknown",
      urgency: "medium",
      preferred_time: "flexible",
      budget_sensitivity: "medium",
      job_complexity_hint: "basic",
      language: "mixed",
      confidence: 0.4,
      clarification_needed: true,
      clarification_question: "Could you tell me what service you need and your location?",
      reasoning: "Could not parse input clearly",
    };
  }

  logIntent(userInput, parsed, Date.now() - traceStart);
  return parsed;
}
