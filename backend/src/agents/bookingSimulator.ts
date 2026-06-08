import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
import { ParsedIntent } from "./intentParser.js";
import { RankedProvider, geocodeLocation } from "./providerMatcher.js";
import { PriceQuote } from "./pricingEngine.js";
import { pushNotification } from "../notifications.js";
import { logScheduling, logStatusChange } from "../logger.js";
import { logTraceEvent } from "../trace.js";
import { applyEvent } from "./reliabilityEngine.js";
import { generateAndSaveProgressMessage } from "./progressAgent.js";
import { parseNaturalLanguageTime, formatPKTTime } from "../utils/timeParser.js";

const bookingsFile = path.join(__dirname, "../../data/mock_bookings.json");
const scheduleFile = path.join(__dirname, "../../data/mock_schedule.json");

export type BookingStatus =
  | "PENDING_PROVIDER"
  | "ACCEPTED"
  | "SCHEDULED"
  | "ARRIVING"
  | "ARRIVED"
  | "IN_PROGRESS"
  | "COMPLETED"
  | "CANCELLED_PROVIDER"
  | "CANCELLED_CUSTOMER"
  | "CANCELLED_TIMEOUT";

export interface Booking {
  booking_id: string;
  provider_id: string;
  provider_name: string;
  customer_id: string;
  service_type: string;
  location: string;
  scheduled_time: string;
  status: BookingStatus;
  final_price: number;
  price_quote: PriceQuote;
  negotiation_thread_id: string | null;
  confirmation_message: string;
  reminder_scheduled_at: string;
  checklist: { item: string; completed: boolean }[];
  created_at: string;
  updated_at: string;
  state_history: { status: BookingStatus; timestamp: string }[];
  agent_messages?: {
    from: "provider_agent" | "customer_agent";
    to: "customer_agent" | "provider_agent";
    status: string;
    message: string;
    timestamp: string;
  }[];
  session_id?: string;
  requested_time?: string;
  time_note?: string;
  // GPS movement simulation fields
  current_lat?: number;
  current_lng?: number;
  customer_lat?: number;
  customer_lng?: number;
  distance_meters?: number;
}

function readBookings(): { bookings: Booking[] } {
  try {
    return JSON.parse(fs.readFileSync(bookingsFile, "utf-8"));
  } catch {
    return { bookings: [] };
  }
}

function writeBookings(data: { bookings: Booking[] }) {
  fs.writeFileSync(bookingsFile, JSON.stringify(data, null, 2));
}

interface ScheduleSlot {
  datetime: string;
  booking_id?: string | null;
  status: "confirmed" | "soft_locked";
  session_id?: string;
}

function readSchedule(): Record<string, ScheduleSlot[]> {
  try {
    const raw = JSON.parse(fs.readFileSync(scheduleFile, "utf-8"));
    // Migrate legacy flat-string arrays on first read
    const out: Record<string, ScheduleSlot[]> = {};
    for (const [id, slots] of Object.entries(raw)) {
      out[id] = (slots as any[]).map((s: any) =>
        typeof s === "string"
          ? { datetime: s.split("::")[0], booking_id: null, status: s.includes("soft_locked") ? "soft_locked" as const : "confirmed" as const }
          : (s as ScheduleSlot)
      );
    }
    return out;
  } catch {
    return {};
  }
}

function writeSchedule(data: Record<string, ScheduleSlot[]>) {
  fs.writeFileSync(scheduleFile, JSON.stringify(data, null, 2));
}

function generateBookingId(): string {
  const date = new Date().toISOString().slice(0, 10).replace(/-/g, "");
  const seq = String(readBookings().bookings.length + 1).padStart(4, "0");
  return `SVC-${date}-${seq}`;
}

// Utility to update provider record in mock_providers.json
export function updateProviderInFile(providerId: string, updates: Partial<any>) {
  const filePath = path.join(__dirname, "../../data/mock_providers.json");
  try {
    const providers = JSON.parse(fs.readFileSync(filePath, "utf-8"));
    const idx = providers.findIndex((p: any) => p.provider_id === providerId || p.id === providerId);
    if (idx !== -1) {
      providers[idx] = { ...providers[idx], ...updates };
      fs.writeFileSync(filePath, JSON.stringify(providers, null, 2));
      console.log(`[BookingSimulator] Saved provider updates for ${providerId} to file:`, updates);
    }
  } catch (err) {
    console.error(`[BookingSimulator] Error saving provider updates:`, err);
  }
}


// Pakistani service worker defaults: Sun–Thu + Sat working, 08:00–20:00, no Fri after 13:00
const AVAIL_WORKING_DAYS = new Set([0, 1, 2, 3, 4, 6]); // 5=Fri excluded as jummah
const AVAIL_START = 8;
const AVAIL_END   = 20;
const JUMMAH_CUTOFF = 13;

function snapToAvailability(d: Date): Date {
  for (let i = 0; i < 14; i++) {
    // Always check availability using PKT hours, regardless of server timezone
    const pktLocal = new Date(d.toLocaleString("en-US", { timeZone: "Asia/Karachi" }));
    const day  = pktLocal.getDay();
    const hour = pktLocal.getHours();
    const pktY  = pktLocal.getFullYear();
    const pktMo = String(pktLocal.getMonth() + 1).padStart(2, '0');
    const pktD  = String(pktLocal.getDate()).padStart(2, '0');

    const advanceToNextDayStart = () =>
      new Date(`${pktY}-${pktMo}-${pktD}T00:00:00+05:00`).valueOf() + 24 * 3_600_000 + AVAIL_START * 3_600_000;

    if (!AVAIL_WORKING_DAYS.has(day) || (day === 5 && hour >= JUMMAH_CUTOFF)) {
      d = new Date(advanceToNextDayStart());
      continue;
    }
    if (hour < AVAIL_START) {
      d = new Date(`${pktY}-${pktMo}-${pktD}T${String(AVAIL_START).padStart(2,'0')}:00:00+05:00`);
      break;
    }
    if (hour >= AVAIL_END) {
      d = new Date(advanceToNextDayStart());
      continue;
    }
    break;
  }
  return d;
}

function getScheduledTime(preferredTime: string, providerId: string, existingSchedule: Record<string, ScheduleSlot[]>): { time: string; collision: boolean; requested_time: string; time_note?: string } {
  const rawDate = parseNaturalLanguageTime(preferredTime);
  const _pktNow = new Date(new Date().toLocaleString("en-US", { timeZone: "Asia/Karachi" }));
  // If the parsed time is within 90 min of now it's effectively "abhi/asap" — skip working-hours snap
  const isImmediate   = rawDate.getTime() - _pktNow.getTime() < 90 * 60 * 1000;
  const requestedDate = isImmediate ? rawDate : snapToAvailability(rawDate);
  const requestedIso  = requestedDate.toISOString();
  let baseTime = requestedDate;

  const providerSlots = existingSchedule[providerId] || [];
  let finalTime = baseTime.toISOString();
  let collision = false;

  while (providerSlots.some(s => s.datetime === finalTime)) {
    collision = true;
    baseTime = snapToAvailability(new Date(baseTime.getTime() + 2 * 60 * 60 * 1000));
    finalTime = baseTime.toISOString();
  }

  const delayMs = new Date(finalTime).getTime() - new Date(requestedIso).getTime();
  const delayMin = Math.round(delayMs / 60000);

  let time_note: string | undefined;
  if (delayMin >= 15) {
    const reqFmt = formatPKTTime(requestedIso);
    const actFmt = formatPKTTime(finalTime);
    time_note = `Requested ${reqFmt} — provider's next free slot is ${actFmt} (${delayMin < 60 ? `${delayMin} min` : `${Math.round(delayMin / 60)}h`} later)`;
  }

  return { time: finalTime, collision, requested_time: requestedIso, time_note };
}

export function softLockSlot(providerId: string, preferredTime: string, sessionId: string): string {
  const schedule = readSchedule();
  const { time: slotTime } = getScheduledTime(preferredTime, providerId, schedule);
  if (!schedule[providerId]) schedule[providerId] = [];
  schedule[providerId].push({ datetime: slotTime, booking_id: null, status: "soft_locked", session_id: sessionId });
  writeSchedule(schedule);
  console.log(`[BookingSimulator] Soft-locked slot ${slotTime} for provider ${providerId}, session ${sessionId}`);
  return slotTime;
}

export function releaseSoftLock(sessionId: string) {
  const schedule = readSchedule();
  let modified = false;
  for (const providerId in schedule) {
    const before = schedule[providerId].length;
    schedule[providerId] = schedule[providerId].filter(s => !(s.status === "soft_locked" && s.session_id === sessionId));
    if (schedule[providerId].length !== before) modified = true;
  }
  if (modified) {
    writeSchedule(schedule);
    console.log(`[BookingSimulator] Released soft-locks for session ${sessionId}`);
  }
}

export function convertSoftLockToHardLock(sessionId: string) {
  const schedule = readSchedule();
  let modified = false;
  for (const providerId in schedule) {
    schedule[providerId] = schedule[providerId].map(s => {
      if (s.status === "soft_locked" && s.session_id === sessionId) {
        modified = true;
        const { session_id: _, ...rest } = s;
        return { ...rest, status: "confirmed" as const };
      }
      return s;
    });
  }
  if (modified) {
    writeSchedule(schedule);
    console.log(`[BookingSimulator] Converted soft-locks to hard-locks for session ${sessionId}`);
  }
}

function getConfirmationMessage(
  booking: Booking,
  language: string
): string {
  const timeNote = booking.time_note ? (language === "roman_urdu" || language === "mixed"
    ? ` ⚠️ Note: ${booking.time_note}`
    : ` ⚠️ Note: ${booking.time_note}`) : "";

  if (language === "roman_urdu" || language === "mixed") {
    return `Booking confirm ho gayi! ${booking.provider_name} aap ke paas ${booking.location} mein ${new Date(booking.scheduled_time).toLocaleString("en-PK")} ko pohunchen ge. Booking ID: ${booking.booking_id}. Total: Rs. ${booking.final_price}.${timeNote}`;
  }
  return `Booking confirmed! ${booking.provider_name} will arrive at ${booking.location} on ${new Date(booking.scheduled_time).toLocaleString("en-PK")}. Booking ID: ${booking.booking_id}. Total: Rs. ${booking.final_price}.${timeNote}`;
}

function getChecklist(serviceType: string): { item: string; completed: boolean }[] {
  const checklists: Record<string, string[]> = {
    ac_repair: ["Diagnose the issue", "Complete repair", "Test AC running", "Clean up area", "Show result to customer"],
    ac_installation: ["Inspect mounting location", "Install AC unit", "Connect wiring", "Test cooling", "Clean up area", "Show result to customer"],
    electrician: ["Identify fault", "Complete electrical work", "Test all connections", "Clean up area"],
    plumber: ["Diagnose leak/blockage", "Complete repair", "Test water flow", "Clean up area"],
    cleaning: ["Clean all surfaces", "Vacuum/mop floors", "Clean bathrooms", "Remove trash", "Final inspection"],
    default: ["Complete the job", "Test/verify work", "Clean up area", "Show result to customer"],
  };

  const items = checklists[serviceType] || checklists.default;
  return items.map((item) => ({ item, completed: false }));
}

// Approximate coordinate mappings for GPS movement simulation

export async function createBooking(
  intent: ParsedIntent,
  provider: RankedProvider,
  priceQuote: PriceQuote,
  finalPrice: number,
  negotiationThreadId: string | null = null,
  customerId: string = "customer_001",
  sessionId?: string
): Promise<{ booking: Booking; before: any; after: any }> {
  const data = readBookings();
  const schedule = readSchedule();
  const before = { bookings_count: data.bookings.length };

  const { time: scheduledTime, collision, requested_time, time_note } = getScheduledTime(intent.preferred_time, provider.provider_id, schedule);
  const bookingId = generateBookingId();

  // Block the slot in schedule
  if (!schedule[provider.provider_id]) schedule[provider.provider_id] = [];
  schedule[provider.provider_id].push({ datetime: scheduledTime, booking_id: bookingId, status: "confirmed" });
  writeSchedule(schedule);

  // Reminder = 1 hour before
  const reminderTime = new Date(new Date(scheduledTime).getTime() - 60 * 60 * 1000).toISOString();

  // Geocode customer location using Nominatim (cached — already called by matchProviders)
  const customerCoords = await geocodeLocation(intent.location);

  // Use the provider's actual coordinates and the matched distance_km as the source of truth
  const providerCoords = provider.location || { latitude: customerCoords.lat + 0.009, longitude: customerCoords.lng - 0.006 };
  let startLat = providerCoords.latitude;
  let startLng = providerCoords.longitude;

  // distance_km from the matcher is authoritative (calculated with geocoded coords)
  // Convert to meters and ensure at least 1 km for a realistic simulation arc
  const matcherDistMeters = Math.round(provider.distance_km * 1000);
  const startDistMeters = Math.max(matcherDistMeters, 1000);

  // Generate JOB DETAIL object with status = PENDING_PROVIDER
  const booking: Booking = {
    booking_id: bookingId,
    provider_id: provider.provider_id,
    provider_name: provider.name,
    customer_id: customerId,
    service_type: intent.service_type,
    location: intent.location,
    scheduled_time: scheduledTime,
    status: "PENDING_PROVIDER",
    final_price: finalPrice,
    price_quote: priceQuote,
    negotiation_thread_id: negotiationThreadId,
    confirmation_message: "",
    reminder_scheduled_at: reminderTime,
    checklist: getChecklist(intent.service_type),
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    state_history: [{ status: "PENDING_PROVIDER", timestamp: new Date().toISOString() }],
    session_id: sessionId,
    requested_time,
    time_note,
    current_lat: startLat,
    current_lng: startLng,
    customer_lat: customerCoords.lat,
    customer_lng: customerCoords.lng,
    distance_meters: startDistMeters,
  };

  booking.confirmation_message = getConfirmationMessage(booking, intent.language);
  data.bookings.push(booking);
  writeBookings(data);

  const after = { bookings_count: data.bookings.length, latest_booking: bookingId };

  logScheduling(provider.provider_id, intent.preferred_time, scheduledTime, bookingId, collision);
  if (sessionId) {
    logTraceEvent(sessionId, {
      agent: "BookingSimulator",
      phase_after: "PENDING_PROVIDER",
      booking_id: bookingId,
      provider_id: provider.provider_id,
      provider_name: provider.name,
      preferred_time_requested: intent.preferred_time,
      scheduled_time_assigned: scheduledTime,
      scheduling_collision_detected: collision,
      final_price: finalPrice,
    });
  }
  console.log(`[BookingSimulator] Created: ${bookingId} | Provider: ${provider.name} | Price: Rs. ${finalPrice}`);

  // Agent auto-accepts on behalf of provider
  updateBookingStatus(bookingId, "ACCEPTED");

  // If booking is >3 hours away, set SCHEDULED — GPS tracking not needed yet
  const pktNow = new Date(new Date().toLocaleString("en-US", { timeZone: "Asia/Karachi" }));
  const hoursAway = (new Date(scheduledTime).getTime() - pktNow.getTime()) / 3_600_000;
  if (hoursAway > 3) updateBookingStatus(bookingId, "SCHEDULED");

  const finalBooking = getBooking(bookingId)!;

  pushNotification(
    "PROVIDER",
    bookingId,
    "job_confirmed",
    "Naya Job Confirm! ✅",
    `${intent.service_type} job ${intent.location} mein schedule ho gaya. Rs. ${finalPrice} — koi action nahi chahiye.`
  );

  return { booking: finalBooking, before, after };
}

// Update booking status (state machine)
export function updateBookingStatus(bookingId: string, newStatus: BookingStatus): Booking {
  const data = readBookings();
  const booking = data.bookings.find((b) => b.booking_id === bookingId);
  if (!booking) throw new Error(`Booking ${bookingId} not found`);

  const prevStatus = booking.status;
  logStatusChange(bookingId, prevStatus, newStatus);
  booking.status = newStatus;
  booking.updated_at = new Date().toISOString();
  booking.state_history.push({ status: newStatus, timestamp: new Date().toISOString() });

  writeBookings(data);

  // ── SLA auto-enforcement: late arrival penalty + auto-credit ──────────
  if (newStatus === "ARRIVED" && booking.scheduled_time) {
    const scheduledMs  = new Date(booking.scheduled_time).getTime();
    const arrivedMs    = Date.now();
    const lateMinutes  = Math.round((arrivedMs - scheduledMs) / 60_000);
    const SLA_LATE_THRESHOLD = 20;
    const SLA_CREDIT_AMOUNT  = 100;
    if (lateMinutes > SLA_LATE_THRESHOLD) {
      (booking as any).sla_breach      = true;
      (booking as any).sla_late_min    = lateMinutes;
      (booking as any).auto_credit_rs  = SLA_CREDIT_AMOUNT;
      console.log(`[SLA] Late arrival: ${lateMinutes} min — auto-credit Rs. ${SLA_CREDIT_AMOUNT} applied to ${bookingId}`);
      try { applyEvent(booking.provider_id, "late_arrival", bookingId); } catch { /* non-fatal */ }
    }
  }

  // Fire-and-forget: generate A2A narrative — don't block the status update
  const _progressStatuses = new Set(["ARRIVING", "ARRIVED", "IN_PROGRESS", "COMPLETED"]);
  if (_progressStatuses.has(newStatus)) {
    generateAndSaveProgressMessage(bookingId, newStatus, booking).catch((err) =>
      console.error("[ProgressAgent] top-level error:", err)
    );
  }

  if (booking.session_id) {
    logTraceEvent(booking.session_id, {
      agent: "StatusMachine",
      phase_after: newStatus,
      booking_id: bookingId,
      status_from: prevStatus,
      status_to: newStatus,
    });
  }
  console.log(`[BookingSimulator] Status updated: ${bookingId} → ${newStatus}`);

  if (newStatus === "ACCEPTED") {
    pushNotification("CUSTOMER", bookingId, "accepted", "Kaam Accept Ho Gaya! ✅", `${booking.provider_name} ne aap ka request accept kar liya hai.`);
  } else if (newStatus === "SCHEDULED") {
    const d = new Date(booking.scheduled_time).toLocaleString("en-PK", { timeZone: "Asia/Karachi", dateStyle: "medium", timeStyle: "short" });
    pushNotification("CUSTOMER", bookingId, "scheduled", "Booking Schedule Ho Gayi! 📅", `${booking.provider_name} ${d} ko aayein ge.`);
  } else if (newStatus === "ARRIVING") {
    pushNotification("CUSTOMER", bookingId, "on_the_way", "Provider Raste Mein Hai! 🛵", `${booking.provider_name} raste mein hai.`);
  } else if (newStatus === "COMPLETED") {
    pushNotification("CUSTOMER", bookingId, "completed", "Kaam Mukammal! 🎉", `${booking.provider_name} ne kaam poora kar diya hai. Please rate karein!`);
  } else if (newStatus === "CANCELLED_PROVIDER") {
    pushNotification("CUSTOMER", bookingId, "cancelled", "Kaam Cancel Ho Gaya ⚠️", `${booking.provider_name} ne booking cancel kar di hai.`);
  }

  // Increment/Decrement Provider Active Jobs when state changes
  if (newStatus === "ACCEPTED") {
    // Increment active jobs
    const filePath = path.join(__dirname, "../../data/mock_providers.json");
    try {
      const providers = JSON.parse(fs.readFileSync(filePath, "utf-8"));
      const p = providers.find((pr: any) => pr.provider_id === booking.provider_id);
      if (p) {
        updateProviderInFile(booking.provider_id, {
          active_jobs: Math.min(p.capacity, (p.active_jobs || 0) + 1),
        });
      }
    } catch (e) {
      console.error(e);
    }
  } else if (newStatus === "COMPLETED" || newStatus === "CANCELLED_PROVIDER" || newStatus === "CANCELLED_CUSTOMER") {
    // Decrement active jobs
    const filePath = path.join(__dirname, "../../data/mock_providers.json");
    try {
      const providers = JSON.parse(fs.readFileSync(filePath, "utf-8"));
      const p = providers.find((pr: any) => pr.provider_id === booking.provider_id);
      if (p) {
        updateProviderInFile(booking.provider_id, {
          active_jobs: Math.max(0, (p.active_jobs || 1) - 1),
        });
      }
    } catch (e) {
      console.error(e);
    }
  }

  return booking;
}

// Store backup provider for cancellation shield
export function setCancellationShield(bookingId: string, backupProviderId: string, backupProviderName: string): void {
  const data = readBookings();
  const idx = data.bookings.findIndex(b => b.booking_id === bookingId);
  if (idx === -1) return;
  (data.bookings[idx] as any).backup_provider_id   = backupProviderId;
  (data.bookings[idx] as any).backup_provider_name = backupProviderName;
  (data.bookings[idx] as any).cancellation_shield  = true;
  writeBookings(data);
}

// Recalculates provider scores upon provider-driven cancellation
export function handleProviderCancellation(bookingId: string): Booking {
  const booking = updateBookingStatus(bookingId, "CANCELLED_PROVIDER");

  // Determine whether provider actually showed up or is a no-show
  const arrivedInHistory = booking.state_history.some(h => h.status === "ARRIVED" || h.status === "ARRIVING");
  const reliabilityEvent = arrivedInHistory ? "cancel_after_accept" : "no_show";
  try { applyEvent(booking.provider_id, reliabilityEvent, bookingId); } catch { /* non-fatal */ }

  return booking;
}

// Recalculates provider scores upon rating submission
export function submitBookingRating(bookingId: string, stars: number, actualArrivalTimeStr: string): Booking {
  const data = readBookings();
  const booking = data.bookings.find((b) => b.booking_id === bookingId);
  if (!booking) throw new Error(`Booking ${bookingId} not found`);

  // Calculate on-time score: actual_arrival <= scheduled_arrival + 10 mins
  const actualArrival = new Date(actualArrivalTimeStr);
  const scheduledArrival = new Date(booking.scheduled_time);
  const isOnTime = actualArrival.getTime() <= (scheduledArrival.getTime() + 10 * 60 * 1000);

  const providerPath = path.join(__dirname, "../../data/mock_providers.json");
  try {
    const providers = JSON.parse(fs.readFileSync(providerPath, "utf-8"));
    const idx = providers.findIndex((p: any) => p.provider_id === booking.provider_id);
    if (idx !== -1) {
      const p = providers[idx];

      const oldRating = p.rating || 4.5;
      const totalReviews = p.total_reviews || 10;
      const newRating = ((oldRating * totalReviews) + stars) / (totalReviews + 1);

      updateProviderInFile(booking.provider_id, {
        rating: Math.round(newRating * 100) / 100,
        total_reviews: totalReviews + 1,
        total_jobs: (p.total_jobs || 10) + 1,
        active_jobs: Math.max(0, (p.active_jobs || 1) - 1),
      });
    }
  } catch (err) {
    console.error(err);
  }

  // Fire reliability engine event — updates EWMA scores and ledger
  try {
    applyEvent(booking.provider_id, isOnTime ? "job_completed_ontime" : "job_completed_late", bookingId);
  } catch { /* non-fatal */ }

  booking.status = "COMPLETED";
  booking.updated_at = new Date().toISOString();
  booking.state_history.push({ status: "COMPLETED", timestamp: new Date().toISOString() });
  writeBookings(data);

  // Customer Agent verifies checklist and releases payment
  const allItemsDone = booking.checklist.every(c => c.completed);
  const paymentMsg: any = allItemsDone
    ? {
        from: "customer_agent",
        to: "provider_agent",
        status: "PAYMENT_CONFIRMED",
        message: `Rs. ${booking.final_price} — tamam checklist items complete hain aur rating submit ho gayi. Payment release ho gayi. Shukriya! ⭐${stars}`,
        timestamp: new Date().toISOString(),
      }
    : {
        from: "customer_agent",
        to: "provider_agent",
        status: "PAYMENT_HELD",
        message: `Rs. ${booking.final_price} — payment abhi hold hai. Checklist mein kuch items incomplete hain. Please complete karein.`,
        timestamp: new Date().toISOString(),
      };

  if (!booking.agent_messages) booking.agent_messages = [];
  booking.agent_messages.push(paymentMsg);
  writeBookings(data);

  if (booking.session_id) {
    const incompleteItems = booking.checklist
      .filter((c: any) => !c.completed)
      .map((c: any) => c.item);

    logTraceEvent(booking.session_id, {
      agent: "CustomerAgent",
      phase_after: paymentMsg.status,
      booking_id: bookingId,
      decision: allItemsDone ? "release_payment" : "hold_payment",
      amount: booking.final_price,
      checklist_complete: allItemsDone,
      incomplete_items: incompleteItems.length > 0 ? incompleteItems : undefined,
      stars_submitted: stars,
      message_sent_to: "provider_agent",
    });

    logTraceEvent(booking.session_id, {
      agent: "RatingEngine",
      phase_after: "COMPLETED",
      booking_id: bookingId,
      provider_id: booking.provider_id,
      stars_submitted: stars,
      on_time: isOnTime,
      payment_status: paymentMsg.status,
    });
  }
  return booking;
}

// Complete checklist item
export function toggleChecklistItem(bookingId: string, itemIndex: number): Booking {
  const data = readBookings();
  const booking = data.bookings.find((b) => b.booking_id === bookingId);
  if (!booking) throw new Error(`Booking ${bookingId} not found`);

  if (booking.checklist[itemIndex]) {
    booking.checklist[itemIndex].completed = !booking.checklist[itemIndex].completed;
  }

  booking.updated_at = new Date().toISOString();
  writeBookings(data);
  return booking;
}

// Keep old name as alias so any other callers don't break
export const completeChecklistItem = toggleChecklistItem;

export function getBooking(bookingId: string): Booking | undefined {
  return readBookings().bookings.find((b) => b.booking_id === bookingId);
}
