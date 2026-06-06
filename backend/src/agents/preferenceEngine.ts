// Customer Preference Engine — persists learned preferences across sessions.
// Written after each completed booking; read by orchestrator to personalize greetings.

import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname  = path.dirname(__filename);
const profilesDir = path.join(__dirname, "../../data/customer_profiles");

export interface CustomerPreference {
  customer_id: string;
  preferred_times: string[];           // e.g. ["morning", "evening"]
  preferred_locations: string[];        // e.g. ["G11", "G10"]
  budget_ceiling: number;              // highest price they've paid
  budget_floor: number;                // lowest price they've paid
  trusted_providers: Array<{ id: string; name: string; times_booked: number }>;
  service_history: Array<{ service_type: string; count: number; last_date: string }>;
  language: string;
  total_bookings: number;
  updated_at: string;
}

function profilePath(customerId: string): string {
  if (!fs.existsSync(profilesDir)) fs.mkdirSync(profilesDir, { recursive: true });
  return path.join(profilesDir, `${customerId}.json`);
}

export function loadPreferences(customerId: string): CustomerPreference | null {
  try {
    const p = profilePath(customerId);
    if (!fs.existsSync(p)) return null;
    return JSON.parse(fs.readFileSync(p, "utf-8"));
  } catch { return null; }
}

export function updatePreferences(customerId: string, booking: any): void {
  try {
    const existing = loadPreferences(customerId) ?? {
      customer_id: customerId,
      preferred_times: [],
      preferred_locations: [],
      budget_ceiling: 0,
      budget_floor: Infinity,
      trusted_providers: [],
      service_history: [],
      language: "roman_urdu",
      total_bookings: 0,
      updated_at: new Date().toISOString(),
    };

    // Preferred time slots
    const timeSlot = _extractTimeSlot(booking.scheduled_time);
    if (timeSlot && !existing.preferred_times.includes(timeSlot)) {
      existing.preferred_times.unshift(timeSlot);
      if (existing.preferred_times.length > 3) existing.preferred_times.pop();
    }

    // Preferred locations
    const loc = booking.location as string;
    if (loc && !existing.preferred_locations.includes(loc)) {
      existing.preferred_locations.unshift(loc);
      if (existing.preferred_locations.length > 5) existing.preferred_locations.pop();
    }

    // Budget range
    const price = booking.final_price as number ?? 0;
    if (price > existing.budget_ceiling) existing.budget_ceiling = price;
    if (price > 0 && price < existing.budget_floor) existing.budget_floor = price;

    // Trusted providers (any provider booked)
    const prov = existing.trusted_providers.find(p => p.id === booking.provider_id);
    if (prov) {
      prov.times_booked += 1;
    } else {
      existing.trusted_providers.push({ id: booking.provider_id, name: booking.provider_name, times_booked: 1 });
    }

    // Service history
    const svc = existing.service_history.find(s => s.service_type === booking.service_type);
    if (svc) {
      svc.count += 1;
      svc.last_date = new Date().toISOString();
    } else {
      existing.service_history.push({ service_type: booking.service_type, count: 1, last_date: new Date().toISOString() });
    }

    existing.total_bookings = (existing.total_bookings ?? 0) + 1;
    existing.updated_at = new Date().toISOString();

    fs.writeFileSync(profilePath(customerId), JSON.stringify(existing, null, 2));
    console.log(`[PreferenceEngine] Updated profile for ${customerId} (${existing.total_bookings} total bookings)`);
  } catch (err: any) {
    console.warn("[PreferenceEngine] Failed to update preferences:", err.message);
  }
}

export function buildPersonalizedGreeting(prefs: CustomerPreference): string {
  const parts: string[] = [];

  // Most booked service
  const topSvc = prefs.service_history.sort((a, b) => b.count - a.count)[0];
  if (topSvc) {
    const svcName = topSvc.service_type.replace(/_/g, " ");
    parts.push(`Aap pehle ${svcName} service use kar chuke hain`);
  }

  // Budget hint
  if (prefs.budget_ceiling > 0 && prefs.budget_floor < Infinity) {
    parts.push(`aap ka budget range Rs. ${prefs.budget_floor}–${prefs.budget_ceiling} raha hai`);
  }

  // Preferred location
  if (prefs.preferred_locations.length > 0) {
    parts.push(`aur aap aksar ${prefs.preferred_locations[0]} mein service lena pasand karte hain`);
  }

  // Trusted provider
  const repeat = prefs.trusted_providers.find(p => p.times_booked > 1);
  if (repeat) {
    parts.push(`Kya aap dobara ${repeat.name} ko prefer karenge?`);
  }

  if (parts.length === 0) return "";
  return parts.join(", ") + ".";
}

function _extractTimeSlot(isoTime: string): string | null {
  try {
    const h = new Date(isoTime).getHours();
    if (h >= 6  && h < 12) return "morning";
    if (h >= 12 && h < 17) return "afternoon";
    if (h >= 17 && h < 21) return "evening";
    return "night";
  } catch { return null; }
}
