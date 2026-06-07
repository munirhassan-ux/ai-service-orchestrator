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

function parseNaturalLanguageTime(preferred: string): Date {
  const pkt = new Date(new Date().toLocaleString("en-US", { timeZone: "Asia/Karachi" }));
  const pktHour = pkt.getHours();
  const s = (preferred ?? "").toLowerCase().trim();

  // Helper: get a Date set to a specific hour today (PKT)
  function todayAt(h: number): Date {
    const d = new Date(pkt);
    d.setHours(h, 0, 0, 0);
    return d;
  }

  // Helper: get a Date N days from today at hour h
  function daysFromNow(n: number, h: number): Date {
    const d = new Date(pkt);
    d.setDate(d.getDate() + n);
    d.setHours(h, 0, 0, 0);
    return d;
  }

  // Helper: get next occurrence of a weekday (0=Sun … 6=Sat)
  function nextWeekday(targetDay: number, h: number): Date {
    const d = new Date(pkt);
    const diff = ((targetDay - d.getDay()) + 7) % 7 || 7;
    d.setDate(d.getDate() + diff);
    d.setHours(h, 0, 0, 0);
    return d;
  }

  // Extract explicit clock hour from string, e.g. "10 baje", "3pm", "14:00", "shaam 4"
  function extractHour(text: string): number | null {
    const m12 = text.match(/(\d{1,2})\s*(?:baje|am|pm|:00)/i);
    const m24 = text.match(/\b([01]?\d|2[0-3]):([0-5]\d)\b/);
    if (m24) return parseInt(m24[1]);
    if (m12) {
      let h = parseInt(m12[1]);
      if (/pm/i.test(text) && h < 12) h += 12;
      if (/am/i.test(text) && h === 12) h = 0;
      // Contextual: if no am/pm, use time-of-day words
      if (!/(am|pm)/i.test(text)) {
        if (/shaam|evening/i.test(text) && h < 12) h += 12;
        if (/raat|night/i.test(text) && h < 9) h += 12;
        if (/dopahar|afternoon/i.test(text) && h < 12) h += 12;
      }
      return h;
    }
    return null;
  }

  // Time-of-day defaults when no exact hour given
  function periodHour(text: string): number {
    if (/subah|morning|صبح/.test(text)) return 10;
    if (/dopahar|afternoon|دوپہر/.test(text)) return 14;
    if (/shaam|evening|شام/.test(text)) return 18;
    if (/raat|night|رات/.test(text)) return 21;
    // Default based on current PKT hour
    if (pktHour >= 6 && pktHour < 12) return 10;
    if (pktHour >= 12 && pktHour < 17) return 14;
    if (pktHour >= 17 && pktHour < 21) return 18;
    return 10; // overnight → next morning default
  }

  const explicitHour = extractHour(s);
  const baseHour = explicitHour ?? periodHour(s);

  // asap / abhi
  if (/^(asap|abhi|فوری|emergency)/.test(s)) {
    return new Date(pkt.getTime() + 2 * 60 * 60 * 1000);
  }

  // today
  if (/^(aaj|today|آج)/.test(s)) {
    const h = explicitHour ?? (pktHour < 20 ? Math.max(pktHour + 2, 10) : 10);
    const t = todayAt(h);
    return t <= pkt ? daysFromNow(1, 10) : t;
  }

  // tomorrow
  if (/^(kal|tomorrow|کل)/.test(s) && !/parson|پرسوں/.test(s)) {
    return daysFromNow(1, baseHour);
  }

  // day after tomorrow
  if (/parson|پرسوں/.test(s)) {
    return daysFromNow(2, baseHour);
  }

  // named weekdays (Roman Urdu + English)
  const dayMap: [RegExp, number][] = [
    [/peer|پیر|monday/i,    1],
    [/mangal|منگل|tuesday/i, 2],
    [/budh|بدھ|wednesday/i,  3],
    [/jumeraat|جمعرات|thursday/i, 4],
    [/jummah|جمعہ|friday/i,  5],
    [/hafta|ہفتہ|saturday/i, 6],
    [/itwaar|اتوار|sunday/i, 0],
  ];
  for (const [re, day] of dayMap) {
    if (re.test(s)) return nextWeekday(day, baseHour);
  }

  // legacy static keys (keep backwards compat)
  if (s === "today_morning")    return todayAt(10);
  if (s === "today_afternoon")  return todayAt(14);
  if (s === "today_evening")    return todayAt(18);
  if (s === "tomorrow_morning") return daysFromNow(1, 10);
  if (s === "tomorrow_afternoon") return daysFromNow(1, 14);

  // flexible / this_week / jab marzi / anytime → tomorrow morning
  return daysFromNow(1, 10);
}

// Pakistani service worker defaults: Sun–Thu + Sat working, 08:00–20:00, no Fri after 13:00
const AVAIL_WORKING_DAYS = new Set([0, 1, 2, 3, 4, 6]); // 5=Fri excluded as jummah
const AVAIL_START = 8;
const AVAIL_END   = 20;
const JUMMAH_CUTOFF = 13;

function snapToAvailability(d: Date): Date {
  for (let i = 0; i < 14; i++) {
    const day  = d.getDay();
    const hour = d.getHours();
    if (!AVAIL_WORKING_DAYS.has(day) || (day === 5 && hour >= JUMMAH_CUTOFF)) {
      d.setDate(d.getDate() + 1);
      d.setHours(AVAIL_START, 0, 0, 0);
      continue;
    }
    if (hour < AVAIL_START) { d.setHours(AVAIL_START, 0, 0, 0); break; }
    if (hour >= AVAIL_END)  { d.setDate(d.getDate() + 1); d.setHours(AVAIL_START, 0, 0, 0); continue; }
    break;
  }
  return d;
}

function getScheduledTime(preferredTime: string, providerId: string, existingSchedule: Record<string, ScheduleSlot[]>): { time: string; collision: boolean } {
  let baseTime = snapToAvailability(parseNaturalLanguageTime(preferredTime));

  const providerSlots = existingSchedule[providerId] || [];
  let finalTime = baseTime.toISOString();
  let collision = false;

  while (providerSlots.some(s => s.datetime === finalTime)) {
    collision = true;
    baseTime = new Date(baseTime.getTime() + 2 * 60 * 60 * 1000);
    snapToAvailability(baseTime);
    finalTime = baseTime.toISOString();
  }

  return { time: finalTime, collision };
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
  if (language === "roman_urdu" || language === "mixed") {
    return `Booking confirm ho gayi! ${booking.provider_name} aap ke paas ${booking.location} mein ${new Date(booking.scheduled_time).toLocaleString("en-PK")} ko pohunchen ge. Booking ID: ${booking.booking_id}. Total: Rs. ${booking.final_price}.`;
  }
  return `Booking confirmed! ${booking.provider_name} will arrive at ${booking.location} on ${new Date(booking.scheduled_time).toLocaleString("en-PK")}. Booking ID: ${booking.booking_id}. Total: Rs. ${booking.final_price}.`;
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

  const { time: scheduledTime, collision } = getScheduledTime(intent.preferred_time, provider.provider_id, schedule);
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
  if (booking.session_id) {
    logTraceEvent(booking.session_id, {
      agent: "RatingEngine",
      phase_after: "COMPLETED",
      booking_id: bookingId,
      provider_id: booking.provider_id,
      stars_submitted: stars,
      on_time: isOnTime,
    });
  }
  return booking;
}

// Complete checklist item
export function completeChecklistItem(bookingId: string, itemIndex: number): Booking {
  const data = readBookings();
  const booking = data.bookings.find((b) => b.booking_id === bookingId);
  if (!booking) throw new Error(`Booking ${bookingId} not found`);

  if (booking.checklist[itemIndex]) {
    booking.checklist[itemIndex].completed = true;
  }

  booking.updated_at = new Date().toISOString();
  writeBookings(data);
  return booking;
}

export function getBooking(bookingId: string): Booking | undefined {
  return readBookings().bookings.find((b) => b.booking_id === bookingId);
}
