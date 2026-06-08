// Recovery Agent — handles provider cancellations after a deal is locked.
// Replaces the silent auto-reassign: apologises in the customer's language,
// offers compensation, then re-runs an A2A auction excluding the canceller.

import { GoogleGenerativeAI } from "@google/generative-ai";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { matchProviders } from "./providerMatcher.js";
import { runNegotiation } from "./negotiationEngine.js";
import { createBooking } from "./bookingSimulator.js";
import { geocodeLocation } from "./providerMatcher.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export type CancellationCause =
  | "provider_emergency"
  | "provider_no_show"
  | "repeated_canceller"
  | "system_failure";

export interface CompensationOffer {
  type: "priority_rematch" | "fee_waiver" | "honour_original_price" | "apology_retry";
  description: string;
  discount_amount: number;
}

export interface RecoveryResult {
  success: boolean;
  apology_message: string;
  compensation: CompensationOffer;
  new_booking?: any;
  new_contract_id?: string;
  attempts_used: number;
  cause: CancellationCause;
}

function readBookings(): any[] {
  const file = path.join(__dirname, "../../data/mock_bookings.json");
  try { return JSON.parse(fs.readFileSync(file, "utf-8")).bookings ?? []; }
  catch { return []; }
}

function classifyCause(provider: any, bookingChainLength: number): CancellationCause {
  if ((provider.no_show_count ?? 0) >= 2) return "provider_no_show";
  if ((provider.cancellation_risk ?? 0) > 0.20 || bookingChainLength > 2) return "repeated_canceller";
  return "provider_emergency";
}

function buildCompensation(cause: CancellationCause, originalPrice: number): CompensationOffer {
  switch (cause) {
    case "provider_emergency":
      return { type: "priority_rematch", description: "Priority re-match — no surge applied.", discount_amount: 0 };
    case "provider_no_show":
      return { type: "fee_waiver", description: "Visit fee waived on your next booking.", discount_amount: 150 };
    case "repeated_canceller":
      return { type: "honour_original_price", description: `Honoured at original price Rs.${originalPrice}.`, discount_amount: 0 };
    default:
      return { type: "apology_retry", description: "System issue — retrying at no extra cost.", discount_amount: 0 };
  }
}

async function generateApology(cause: CancellationCause, language: string, compensation: CompensationOffer): Promise<string> {
  try {
    const genAI = new GoogleGenerativeAI(process.env.GOOGLE_API_KEY!);
    const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });
    const lang  = language === "english" ? "English" : "Roman Urdu";
    const prompt = `You are Haazir's Recovery Agent. Write a warm, empathetic 2-sentence apology in ${lang} for a provider cancellation.
Cause: ${cause.replace(/_/g, " ")}. Compensation offered: ${compensation.description}.
Do NOT mention provider name. Do NOT use markdown.`;
    const res = await model.generateContent(prompt);
    return res.response.text().trim();
  } catch {
    return language === "english"
      ? `We sincerely apologise for the cancellation. We are finding you a replacement immediately — ${compensation.description}`
      : `Haazir ko bahut afsos hai ke provider ne cancel kar diya. Hum abhi naya provider dhundh rahe hain — ${compensation.description}`;
  }
}

const C = { reset: "\x1b[0m", bold: "\x1b[1m", red: "\x1b[31m", yellow: "\x1b[33m", cyan: "\x1b[36m", green: "\x1b[32m", dim: "\x1b[2m" };
const tag = `${C.yellow}${C.bold}[Recovery]${C.reset}`;

export async function handle(
  cancelledBookingId: string,
  providersTriedSoFar: string[],
  language = "roman_urdu"
): Promise<RecoveryResult> {
  const bookings  = readBookings();
  const booking   = bookings.find((b: any) => b.booking_id === cancelledBookingId);
  if (!booking) throw new Error(`Booking ${cancelledBookingId} not found`);

  const providersFile = path.join(__dirname, "../../data/mock_providers.json");
  const providers = JSON.parse(fs.readFileSync(providersFile, "utf-8"));
  const cancelledProvider = providers.find((p: any) => p.provider_id === booking.provider_id);

  const chainLength = providersTriedSoFar.length;
  const cause = classifyCause(cancelledProvider ?? {}, chainLength);
  const compensation = buildCompensation(cause, booking.final_price);

  console.log(`\n${tag} ━━━ Provider Cancellation Received ━━━`);
  console.log(`${tag} Booking : ${C.bold}${cancelledBookingId}${C.reset}  Customer: ${booking.customer_id}`);
  console.log(`${tag} Service : ${booking.service_type} @ ${booking.location}  |  Price: Rs.${booking.final_price}`);
  console.log(`${tag} Canceller: ${C.red}${cancelledProvider?.name ?? booking.provider_id}${C.reset}  (attempt ${chainLength + 1})`);
  console.log(`${tag} Cause   : ${C.bold}${cause}${C.reset}`);
  console.log(`${tag} Compensation: ${compensation.type} — ${compensation.description}`);

  console.log(`${tag} Generating apology (${language})...`);
  const apologyMessage = await generateApology(cause, language, compensation);
  console.log(`${tag} Apology : "${C.dim}${apologyMessage.slice(0, 80)}${apologyMessage.length > 80 ? "…" : ""}${C.reset}"`);

  // Re-run matching excluding all tried providers
  const intent = booking.parsed_intent ?? {
    service_type: booking.service_type,
    location:     booking.location,
    urgency:      "medium",
    preferred_time: booking.scheduled_time ?? "flexible",
  };

  const allExcluded = [...new Set([...providersTriedSoFar, booking.provider_id])];
  console.log(`${tag} Re-matching for ${intent.service_type} @ ${intent.location}  (excluding ${allExcluded.length} provider${allExcluded.length !== 1 ? "s" : ""})...`);

  try {
    const matchResult = await matchProviders(intent, allExcluded);
    if (matchResult.top_providers.length === 0) {
      console.log(`${tag} ${C.red}No candidates found — recovery failed.${C.reset}\n`);
      return { success: false, apology_message: apologyMessage, compensation, attempts_used: chainLength + 1, cause };
    }

    console.log(`${tag} ${matchResult.top_providers.length} candidate(s) found → running A2A negotiation...`);
    const coords = await geocodeLocation(intent.location);
    const negotiationResult = await runNegotiation(
      matchResult.top_providers,
      intent,
      booking.customer_id,
      coords.lat,
      coords.lng
    );

    const newProvider = negotiationResult.contract
      ? matchResult.top_providers.find(p => p.provider_id === negotiationResult.contract!.provider_id)!
        ?? matchResult.top_providers[0]
      : matchResult.top_providers[0];

    const honourPrice = cause === "repeated_canceller";
    const agreedPrice = honourPrice
      ? Math.min(booking.final_price, negotiationResult.contract?.agreed_price ?? booking.final_price)
      : (negotiationResult.contract?.agreed_price ?? (newProvider.price_quote?.total ?? booking.final_price));

    console.log(`${tag} Negotiation complete — winner: ${C.green}${C.bold}${newProvider.name}${C.reset} @ Rs.${agreedPrice}${honourPrice ? " (price honoured)" : ""}`);
    if (negotiationResult.contract) {
      console.log(`${tag} Contract : ${negotiationResult.contract.contract_id}  |  ${negotiationResult.trace?.rounds ?? "?"} round(s)`);
    }

    const { booking: newBooking } = await createBooking(
      intent,
      newProvider,
      newProvider.price_quote ?? booking.price_quote,
      agreedPrice,
      null,
      booking.customer_id,
      booking.session_id
    );

    console.log(`${tag} ${C.green}${C.bold}✅ Recovery complete — new booking: ${newBooking.booking_id}${C.reset}\n`);

    return {
      success:         true,
      apology_message: apologyMessage,
      compensation,
      new_booking:     newBooking,
      new_contract_id: negotiationResult.contract?.contract_id,
      attempts_used:   chainLength + 1,
      cause,
    };
  } catch (err: any) {
    console.log(`${tag} ${C.red}Recovery failed — ${err.message}${C.reset}\n`);
    return { success: false, apology_message: apologyMessage, compensation, attempts_used: chainLength + 1, cause };
  }
}
