import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { applyEvent } from "./reliabilityEngine.js";
import { updateBookingStatus } from "./bookingSimulator.js";
import { pushNotification } from "../notifications.js";
import { logTraceEvent } from "../trace.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const bookingsFile = path.join(__dirname, "../../data/mock_bookings.json");

const WARN_AFTER_MIN   = 25;
const NOSHOW_AFTER_MIN = 50;
const FUTURE_GRACE_MIN = 20;

const warnedBookings  = new Set<string>();
const noshowBookings  = new Set<string>();

function readBookings(): any[] {
  try { return JSON.parse(fs.readFileSync(bookingsFile, "utf-8")).bookings; }
  catch { return []; }
}

function appendAgentMessage(bookingId: string, message: any) {
  try {
    const raw  = JSON.parse(fs.readFileSync(bookingsFile, "utf-8"));
    const idx  = raw.bookings.findIndex((b: any) => b.booking_id === bookingId);
    if (idx === -1) return;
    if (!raw.bookings[idx].agent_messages) raw.bookings[idx].agent_messages = [];
    raw.bookings[idx].agent_messages.push(message);
    fs.writeFileSync(bookingsFile, JSON.stringify(raw, null, 2));
  } catch { /* non-fatal */ }
}

export function startSlaMonitor(): void {
  setInterval(() => {
    const now      = Date.now();
    const bookings = readBookings();

    for (const b of bookings) {
      if (noshowBookings.has(b.booking_id)) continue;

      const isActiveAccepted  = b.status === "ACCEPTED";
      const isActiveScheduled = b.status === "SCHEDULED";
      if (!isActiveAccepted && !isActiveScheduled) continue;

      const scheduledMs = new Date(b.scheduled_time).getTime();
      const lastChange  = new Date(b.updated_at).getTime();
      const minutesSinceLastChange = (now - lastChange) / 60_000;
      const minutesPastScheduled   = (now - scheduledMs) / 60_000;

      if (isActiveAccepted) {
        if (!warnedBookings.has(b.booking_id) && minutesSinceLastChange >= WARN_AFTER_MIN) {
          warnedBookings.add(b.booking_id);
          console.log(`[SlaMonitor] Warning: ${b.booking_id} stuck ACCEPTED for ${Math.round(minutesSinceLastChange)} min`);

          appendAgentMessage(b.booking_id, {
            from: "customer_agent",
            to: "provider_agent",
            status: "SLA_WARNING",
            message: `Provider se abhi tak koi update nahi mila — ${Math.round(minutesSinceLastChange)} minute guzar gaye hain. Kya aap theek hain? Please status update karein.`,
            timestamp: new Date().toISOString(),
          });

          pushNotification(
            "CUSTOMER", b.booking_id, "sla_warning",
            "Provider Ka Koi Jawab Nahi ⚠️",
            `${b.provider_name} ne ${Math.round(minutesSinceLastChange)} minute se koi update nahi di. Hum monitor kar rahe hain.`
          );

          if (b.session_id) {
            logTraceEvent(b.session_id, {
              agent: "SlaMonitor",
              phase_after: "SLA_WARNING",
              booking_id: b.booking_id,
              provider_id: b.provider_id,
              provider_name: b.provider_name,
              trigger: "accepted_stuck",
              minutes_since_last_change: Math.round(minutesSinceLastChange),
              threshold_min: WARN_AFTER_MIN,
            });
          }
        }

        if (minutesSinceLastChange >= NOSHOW_AFTER_MIN) {
          noshowBookings.add(b.booking_id);
          console.log(`[SlaMonitor] No-show: ${b.booking_id} — marking CANCELLED_TIMEOUT`);

          try { applyEvent(b.provider_id, "no_show", b.booking_id); } catch { /* non-fatal */ }
          updateBookingStatus(b.booking_id, "CANCELLED_TIMEOUT");

          appendAgentMessage(b.booking_id, {
            from: "customer_agent",
            to: "provider_agent",
            status: "SLA_BREACH",
            message: `SLA breach: provider ne ${Math.round(minutesSinceLastChange)} minute mein koi response nahi diya. Booking automatically cancel ho gayi hai aur reliability score update ho gaya hai.`,
            timestamp: new Date().toISOString(),
          });

          pushNotification(
            "CUSTOMER", b.booking_id, "sla_breach",
            "Booking Cancel — Provider No-Show 🚫",
            `${b.provider_name} ne respond nahi kiya. Booking cancel ho gayi. Hum naya provider dhundhne ki koshish karein ge.`
          );

          if (b.session_id) {
            logTraceEvent(b.session_id, {
              agent: "SlaMonitor",
              phase_after: "CANCELLED_TIMEOUT",
              booking_id: b.booking_id,
              provider_id: b.provider_id,
              provider_name: b.provider_name,
              trigger: "no_show_immediate",
              minutes_since_last_change: Math.round(minutesSinceLastChange),
              threshold_min: NOSHOW_AFTER_MIN,
              reliability_event: "no_show",
              action: "auto_cancelled",
            });
          }
        }

      } else if (isActiveScheduled && minutesPastScheduled >= FUTURE_GRACE_MIN) {
        noshowBookings.add(b.booking_id);
        console.log(`[SlaMonitor] Scheduled no-show: ${b.booking_id} — ${Math.round(minutesPastScheduled)} min past scheduled_time`);

        try { applyEvent(b.provider_id, "no_show", b.booking_id); } catch { /* non-fatal */ }
        updateBookingStatus(b.booking_id, "CANCELLED_TIMEOUT");

        appendAgentMessage(b.booking_id, {
          from: "customer_agent",
          to: "provider_agent",
          status: "SLA_BREACH",
          message: `Scheduled time guzar gaya — provider ne ${Math.round(minutesPastScheduled)} minute baad bhi status update nahi ki. Booking cancel ho gayi.`,
          timestamp: new Date().toISOString(),
        });

        pushNotification(
          "CUSTOMER", b.booking_id, "sla_breach",
          "Provider Waqt Par Nahi Aaya 🚫",
          `${b.provider_name} scheduled time ke ${Math.round(minutesPastScheduled)} minute baad bhi appear nahi hua. Booking cancel ho gayi.`
        );

        if (b.session_id) {
          logTraceEvent(b.session_id, {
            agent: "SlaMonitor",
            phase_after: "CANCELLED_TIMEOUT",
            booking_id: b.booking_id,
            provider_id: b.provider_id,
            provider_name: b.provider_name,
            trigger: "no_show_scheduled",
            minutes_past_scheduled: Math.round(minutesPastScheduled),
            grace_period_min: FUTURE_GRACE_MIN,
            scheduled_time: b.scheduled_time,
            reliability_event: "no_show",
            action: "auto_cancelled",
          });
        }
      }
    }
  }, 2 * 60 * 1000);

  console.log("[SlaMonitor] Started — checking every 2 min");
}
