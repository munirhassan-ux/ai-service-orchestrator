// Progress Agent — generates A2A narrative messages during job execution.
// Uses template strings instead of Gemini to avoid rate limits and keep latency near zero.
// Each message is written to disk independently — fire-and-forget safe.

import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const bookingsFile = path.join(__dirname, "../../data/mock_bookings.json");

export interface AgentMessage {
  from: "provider_agent" | "customer_agent";
  to:   "customer_agent" | "provider_agent";
  status: string;
  message: string;
  timestamp: string;
}

function km(meters: number) {
  return (Math.round(meters / 100) / 10).toFixed(1);
}

function buildMessage(status: string, b: any): AgentMessage[] {
  const svc     = (b.service_type ?? "service").replace(/_/g, " ");
  const loc     = b.location ?? "your location";
  const price   = b.final_price ?? "—";
  const distKm  = km(b.distance_meters ?? 1500);

  switch (status) {
    case "ARRIVING":
      return [{
        from: "provider_agent", to: "customer_agent", status,
        message: `Raste mein hun! ${loc} tak pohonchne mein thodi der lagay gi — abhi approximately ${distKm} km door hun. Tayar rahein 🛵`,
        timestamp: new Date().toISOString(),
      }];

    case "ARRIVED":
      return [{
        from: "provider_agent", to: "customer_agent", status,
        message: `${loc} par pohonch gaya hun — ${svc} ka kaam shuru karne ke liye tayar hun. Please andar aanay dein 📍`,
        timestamp: new Date().toISOString(),
      }];

    case "IN_PROGRESS":
      return [{
        from: "provider_agent", to: "customer_agent", status,
        message: `${svc} ka kaam shuru kar diya hai 🔧 Mukammal hone par update karunga.`,
        timestamp: new Date().toISOString(),
      }];

    case "COMPLETED": {
      const allDone = !b.checklist || b.checklist.length === 0 || b.checklist.every((i: any) => i.completed);
      const unpaid  = b.checklist?.filter((i: any) => !i.completed).map((i: any) => i.item) ?? [];

      const providerMsg = allDone
        ? `Kaam mukammal ho gaya ✅ Tamam checklist items complete hain. Meherbani kar ke payment Rs. ${price} confirm karein aur rating dein taakay funds release ho sakain.`
        : `Kaam mukammal mark kar diya hai lekin ${unpaid.length} item(s) abhi incomplete hain: ${unpaid.join(", ")}. Payment abhi hold hai.`;

      return [{
        from: "provider_agent", to: "customer_agent", status,
        message: providerMsg,
        timestamp: new Date().toISOString(),
      }];
    }

    default:
      return [];
  }
}

function appendMessages(bookingId: string, messages: AgentMessage[]): void {
  if (messages.length === 0) return;
  const data = JSON.parse(fs.readFileSync(bookingsFile, "utf-8"));
  const idx = data.bookings.findIndex((b: any) => b.booking_id === bookingId);
  if (idx === -1) return;
  if (!data.bookings[idx].agent_messages) data.bookings[idx].agent_messages = [];
  data.bookings[idx].agent_messages.push(...messages);
  fs.writeFileSync(bookingsFile, JSON.stringify(data, null, 2));
  messages.forEach(m =>
    console.log(`[ProgressAgent] Saved: ${bookingId} → ${m.status} (${m.from})`)
  );
}

export async function generateAndSaveProgressMessage(
  bookingId: string,
  status: string,
  booking: any
): Promise<void> {
  try {
    const messages = buildMessage(status, booking);
    appendMessages(bookingId, messages);
  } catch (err: any) {
    console.warn(`[ProgressAgent] Failed for ${status}:`, err.message);
  }
}
