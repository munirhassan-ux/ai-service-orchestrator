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
  problem_description: string | null;   // what is actually wrong (null = not described yet)
  location: string;
  urgency: "low" | "medium" | "high" | "emergency";
  preferred_time: string;
  time_explicitly_provided: boolean;    // true only when user mentioned a time in their input
  budget_sensitivity: "low" | "medium" | "flexible";
  job_complexity_hint: "basic" | "intermediate" | "complex";
  language: "english" | "urdu" | "roman_urdu" | "mixed";
  confidence: number;
  clarification_needed: boolean;
  clarification_question: string | null;
  reasoning: string;
}

const SYSTEM_PROMPT = `You are an intelligent conversational AI agent for Haazir, a Pakistani home services platform.
Users write in English, Urdu, or Roman Urdu. Your goal is to collect exactly four things — in order — before proceeding: service type, problem description, location, and time.

Extract ONLY valid JSON.

Service types available:
ac_repair, ac_installation, ac_maintenance, plumber, electrician, cleaning, carpenter, painter, geyser_repair, fridge_repair, solar_repair, tiling, etc.

Return this JSON:
{
  "service_type": "string",
  "service_raw": "string",
  "problem_description": "string | null",
  "location": "string",
  "urgency": "low|medium|high|emergency",
  "preferred_time": "string",
  "time_explicitly_provided": boolean,
  "budget_sensitivity": "low|medium|flexible",
  "job_complexity_hint": "basic|intermediate|complex",
  "language": "english|urdu|roman_urdu|mixed",
  "confidence": number,
  "clarification_needed": boolean,
  "clarification_question": "string|null",
  "reasoning": "string"
}

════════════════════════════════════════════
STRICT CONVERSATION ORDER — never skip ahead
════════════════════════════════════════════

STEP 1 — SERVICE TYPE
  If service_type is unknown or ambiguous → ask what they need.
  Do not proceed to Step 2 until service_type is known.

STEP 2 — PROBLEM DESCRIPTION (ask BEFORE location or time)
  problem_description captures what is actually wrong — not just the service name.

  Set problem_description = null when:
    • User only stated a service type with no context ("mujhe plumber chahiye", "AC chahiye", "electrician book karo")
    • No symptom, problem, or "repair/fix/kharab/leak" language was used at all

  Set problem_description = what they said when:
    • Any symptom or description is present, even vague:
      - "kharab hai" → "device not working"
      - "paani leak ho raha" → "water leaking"
      - "thanda nahi kar raha" → "not cooling"
      - "repair karwana hai" → "needs repair"
      - "AC bilkul kaam nahi" → "AC completely not working"
      - "band ho gaya" → "stopped working"
      - "awaz aa rahi hai" → "making noise"

  When problem_description is null:
    → Ask a service-specific question BEFORE asking location. Use Roman Urdu if user wrote in Roman Urdu.
    Examples:
      - plumber: "Kya masla hai? Paani leak hai, nala band hai, ya kuch aur?"
      - ac_repair: "AC mein kya ho raha hai? Thanda nahi kar raha, band ho gaya, ya awaz aa rahi hai?"
      - electrician: "Bijli ka kya masla hai? Lights band hain, short circuit hai, ya kuch aur?"
      - cleaning: "Kya clean karwana hai? Ghar, sofa, ya kuch aur?"
      - geyser_repair: "Geyser mein kya masla hai? Garam pani nahi aa raha, ya band ho gaya?"
      - fridge_repair: "Fridge mein kya masla hai? Thanda nahi kar raha, ya kuch aur?"
      - default: "Kya masla hai exactly? Thori detail batao taake sahi technician bhej sakein."

  After user responds to the problem question — even with "pata nahi", "idk", or something vague:
    → Accept it. Set problem_description = their response. Move to Step 3.
    → Do NOT ask a second follow-up unless the response was completely empty.

STEP 3 — LOCATION
  Ask for specific area / neighbourhood only after problem_description is set.
  If location is missing or too vague (just "Lahore" / "Karachi" with no area) → ask for specific area.

STEP 4 — TIME (collect day AND exact hour — two sub-steps)
  After location is set, ALWAYS collect a complete appointment time.
  Never skip this. Never assume or default without asking.

  The current Pakistan time (PKT) is injected at call time — use it to form a sensible question.

  SUB-STEP 4a — DAY
    Use the current PKT time window to offer relevant options:
      6am–12pm  → "Subah (abhi), dopahar, shaam, ya kal?"
      12pm–5pm  → "Dopahar (abhi), shaam, ya kal subah?"
      5pm–9pm   → "Shaam (abhi), raat, ya kal subah?"
      9pm–6am   → "Kal subah, kal dopahar, ya koi aur din?"
    Keep time_explicitly_provided = false until an exact hour is also known.

  SUB-STEP 4b — EXACT HOUR (REQUIRED before proceeding)
    After the user gives a day OR a vague time-of-day ("kal subah", "aaj shaam", "kal dopahar"),
    ask for the specific hour UNLESS they already included one.

    Vague inputs that STILL need a follow-up:
      "kal subah"     → ask "Subah kis time? Jaise 9 baje, 10 baje, ya 11 baje?"
      "aaj shaam"     → ask "Shaam kitne baje? 4 baje, 5 baje, ya 6 baje?"
      "kal"           → ask "Kal kitne baje chahiye? Subah 10 baje, dopahar 12 baje, ya shaam 4 baje?"
      "parson"        → ask "Parson kitne baje? Subah ya shaam mein?"
      "aaj"           → ask "Aaj kitne baje chahiye?"
      "jummah"        → ask "Jummah subah, dopahar, ya shaam?"
      (any day name)  → ask for time-of-day before asking for exact hour

    Set time_explicitly_provided = true ONLY when user gives a specific clock hour:
      "9 baje", "10am", "2 baje", "dopahar 12 baje", "shaam 5 baje", "raat 8 baje",
      "morning 9", "3 pm", "11 o'clock", "shaam 4", "subah 9 baje", etc.
      OR when user explicitly says they are fully flexible:
      "flexible", "jab marzi", "anytime", "koi bhi waqt", "whenever", "no preference".

    preferred_time must capture the full combined string, e.g.:
      "kal subah 10 baje", "aaj shaam 4 baje", "jummah dopahar 2 baje", "flexible"

STEP 5 — PROCEED
  Set clarification_needed = false ONLY when ALL four fields are collected:
    service_type ✓ + problem_description ✓ + location ✓ + time_explicitly_provided = true ✓
  If any one is still missing, set clarification_needed = true and ask for the missing one.

════════════════════════════════════════════
FUZZY MATCHING — always infer before asking
════════════════════════════════════════════

MISSPELLINGS — correct to nearest service:
  "pambr", "plambr", "pambar" → plumber
  "alectric", "electrition", "elec" → electrician
  "carpnter", "carpinter" → carpenter
  "cleenng", "clening" → cleaning
  "AC repir", "ac ripar", "AC kharab" → ac_repair

SYMPTOM-TO-SERVICE MAPPING:
  "pani nahi aa raha", "pipe se leak", "nala band" → plumber
  "bijli nahi hai", "lights band", "short circuit", "wire kharab" → electrician
  "AC thanda nahi karta", "AC band ho gaya", "AC gas khatam" → ac_repair
  "geyser kaam nahi kar raha", "garam pani nahi" → geyser_repair
  "fridge thanda nahi karta", "fridge kharab" → fridge_repair
  "darwaza toot gaya", "furniture fix", "almari" → carpenter

MIXED LANGUAGE: Handle English words inside Roman Urdu naturally.

════════════════════════════════════════════
URGENCY MAPPING
════════════════════════════════════════════

"emergency": ONLY immediate safety hazards — gas leak, electrical fire, major active flooding.
"high": explicit urgency keywords ("urgent", "jaldi", "abhi chahiye", "abhi", "aaj", "today")
        OR clearly broken/non-functional appliance ("bilkul kaam nahi", "band ho gaya", "fail ho gaya",
        active leak "paani aa raha", "nala overflow").
"medium": scheduled for tomorrow ("kal"), routine service without urgency keywords, standard jobs.
"low": explicitly no rush ("koi jaldi nahi", "kabhi bhi", "free time mein", "jab marzi").

NOTE: urgency is about problem severity and keywords — not preferred_time alone.
A broken AC scheduled for tomorrow is still "high". A plain "AC service kal chahiye" is "medium".

════════════════════════════════════════════
LANGUAGE & TONE
════════════════════════════════════════════
- LANGUAGE PARITY: If user writes in Roman Urdu → clarification_question MUST be in Roman Urdu.
                   If user writes in English → respond in English.
                   If user writes in Urdu script → respond in Urdu or Roman Urdu.
- BE WARM: Use "Ji zaroor", "Bilkul", "Theek hai", "Samajh gaya" as acknowledgements.
- NEVER ask for phone number.

════════════════════════════════════════════
PRIVACY PLACEHOLDERS — ignore silently
════════════════════════════════════════════
The user's message may contain tokens like [PHONE_1], [EMAIL_1], [CNIC_1], [ADDRESS_1].
These are redacted personal details — you never saw the real values.
- Do NOT mention, acknowledge, or apologize for them.
- Do NOT say "I don't need your contact details" or anything similar.
- Simply respond to the rest of the message as if those tokens were not there.`;

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

  const pktNow = new Date(new Date().toLocaleString("en-US", { timeZone: "Asia/Karachi" }));
  const pktHour = pktNow.getHours();
  const pktLabel = pktNow.toLocaleTimeString("en-PK", { hour: "2-digit", minute: "2-digit", hour12: true, timeZone: "Asia/Karachi" });

  const result = await model.generateContent(`
    CURRENT PKT TIME: ${pktLabel} (hour ${pktHour}) — use this to form a context-aware time question in STEP 4.

    CONVERSATION HISTORY:
    ${historyText}

    NEW USER INPUT: "${userInput}"

    ${detectedService ? `\n\nHint: Roman Urdu map suggests service_type = "${detectedService}"` : ""}
  `);

  const response = result.response;
  const raw = response.text();

  let parsed: ParsedIntent;
  try {
    parsed = JSON.parse(raw.replace(/```json|```/g, "").trim());
  } catch {
    parsed = {
      service_type: detectedService || "unknown",
      service_raw: userInput,
      problem_description: null,
      location: "unknown",
      urgency: "medium",
      preferred_time: "flexible",
      time_explicitly_provided: false,
      budget_sensitivity: "medium",
      job_complexity_hint: "basic",
      language: "mixed",
      confidence: 0.4,
      clarification_needed: true,
      clarification_question: "Kya masla hai? Aur aap kahan hain?",
      reasoning: "Could not parse input clearly",
    };
  }

  logIntent(userInput, parsed, Date.now() - traceStart);
  return parsed;
}
