import { GoogleGenerativeAI } from "@google/generative-ai";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { logProviderMatch } from "../logger.js";
import { computeScore } from "./reliabilityEngine.js";
import { parseNaturalLanguageTime } from "../utils/timeParser.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
import { ParsedIntent } from "./intentParser.js";

// Maps intent service_type values to actual service_expertise keys in mock data
const SERVICE_ALIASES: Record<string, string[]> = {
  painter:          ["house_painting", "wall_painting", "interior_painting", "exterior_painting"],
  painting:         ["house_painting", "wall_painting", "interior_painting", "exterior_painting"],
  tiling:           ["tiling", "tile_installation", "carpenter"],
  fridge_repair:    ["fridge_repair", "refrigerator_repair", "ac_repair"],
  solar_repair:     ["solar_repair", "solar_maintenance"],
  solar_installation: ["solar_installation", "solar_maintenance"],
  deep_cleaning:    ["deep_cleaning", "home_cleaning"],
  sofa_cleaning:    ["sofa_cleaning", "carpet_cleaning", "home_cleaning"],
  office_cleaning:  ["office_cleaning", "home_cleaning"],
  cctv:             ["cctv_installation", "cctv_repair", "security_systems"],
  inverter:         ["inverter_repair", "generator_repair"],
  geyser_repair:    ["geyser_repair", "gas_repair"],
};

function resolveServiceTypes(serviceType: string): string[] {
  const lower = serviceType.toLowerCase();
  return SERVICE_ALIASES[lower] ?? [lower];
}

function matchesServiceType(expertise: string[], serviceType: string): boolean {
  const targets = resolveServiceTypes(serviceType);
  const prefix = serviceType.toLowerCase().split("_")[0];
  return expertise.some(s => {
    const sl = s.toLowerCase();
    return targets.includes(sl) || sl === serviceType.toLowerCase() || sl.startsWith(prefix);
  });
}

function getProvidersData() {
  const filePath = path.join(__dirname, "../../data/mock_providers.json");
  return JSON.parse(fs.readFileSync(filePath, "utf-8"));
}

// Real-time active booking counts — more accurate than cached active_jobs field
function getLiveActiveBookingCounts(): Record<string, number> {
  const bookingsFile = path.join(__dirname, "../../data/mock_bookings.json");
  const occupied = new Set(["PENDING_PROVIDER", "ACCEPTED", "ARRIVING", "ARRIVED", "IN_PROGRESS"]);
  try {
    const data = JSON.parse(fs.readFileSync(bookingsFile, "utf-8"));
    const counts: Record<string, number> = {};
    for (const b of data.bookings) {
      if (occupied.has(b.status)) {
        counts[b.provider_id] = (counts[b.provider_id] || 0) + 1;
      }
    }
    return counts;
  } catch {
    return {};
  }
}

// Detect time-window conflicts: provider already has an active booking within ±2h of requested slot
const MAX_WAIT_MS = 4 * 3600000; // providers >4h later than requested are waitlisted
const SLOT_WINDOW_MS = 2 * 3600000; // 2-hour slot window around each booking

// Build a combined booked-slots map from both bookings and schedule files
function buildBookedSlotsMap(): Record<string, number[]> {
  const bookingsFile = path.join(__dirname, "../../data/mock_bookings.json");
  const scheduleFile = path.join(__dirname, "../../data/mock_schedule.json");
  const occupied = new Set(["PENDING_PROVIDER", "ACCEPTED", "ARRIVING", "ARRIVED", "IN_PROGRESS", "SCHEDULED"]);
  const slots: Record<string, number[]> = {};

  try {
    const data = JSON.parse(fs.readFileSync(bookingsFile, "utf-8"));
    for (const b of data.bookings) {
      if (occupied.has(b.status) && b.scheduled_time) {
        if (!slots[b.provider_id]) slots[b.provider_id] = [];
        slots[b.provider_id].push(new Date(b.scheduled_time).getTime());
      }
    }
  } catch { /* no-op */ }

  try {
    const sched = JSON.parse(fs.readFileSync(scheduleFile, "utf-8"));
    for (const [providerId, entries] of Object.entries(sched as Record<string, any[]>)) {
      for (const e of entries) {
        if (e.datetime && e.status !== "soft_locked") {
          if (!slots[providerId]) slots[providerId] = [];
          const ms = new Date(e.datetime).getTime();
          if (!slots[providerId].includes(ms)) slots[providerId].push(ms);
        }
      }
    }
  } catch { /* no-op */ }

  return slots;
}

// Given a provider's booked slots and a requested time, return their earliest free slot at or after requestedMs
function getNextAvailableSlotMs(providerId: string, requestedMs: number, slots: Record<string, number[]>): number {
  let candidate = requestedMs;
  const provSlots = slots[providerId] || [];

  for (let i = 0; i < 10; i++) {
    const conflict = provSlots.find(t => Math.abs(t - candidate) < SLOT_WINDOW_MS);
    if (!conflict) return candidate;
    candidate = conflict + SLOT_WINDOW_MS;
  }
  return candidate;
}

export interface RankedProvider {
  provider_id: string;
  name: string;
  shop_name: string;
  location: { latitude: number; longitude: number };
  city: string;
  city_area: string;
  availability_status: "online" | "offline";
  charges: {
    base_rate: number;
    travel_rate: number;
  };
  job_role: string;
  service_expertise: string[];
  rating: number;
  on_time_score: number;
  cancellation_risk: number;
  capacity: number;
  active_jobs: number;
  total_reviews: number;
  total_jobs: number;
  distance_km: number;
  score: number;
  score_breakdown: {
    travel_time: number;
    availability_match: number;
    specialization: number;
    on_time: number;
    review_sentiment: number;
    rate: number;
    cancellation_risk: number;
    capacity: number;
  };
  is_waitlisted?: boolean;
  price_quote?: any;
  reliability_score?: number;
  completion_rate?: number;
  next_available_slot_ms?: number;
  slot_delay_min?: number;
}

export interface MatchResult {
  top_providers: RankedProvider[];
  reasoning: string;
  fallback_used: boolean;
  fallback_reason?: string;
  matching_trace: string;
}

// Haversine formula — distance between two lat/lng points in km
function haversine(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
    Math.cos((lat2 * Math.PI) / 180) *
    Math.sin(dLng / 2) *
    Math.sin(dLng / 2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Static fallback table — used instantly if location matches, avoiding a network call
const _staticCoords: Record<string, { lat: number; lng: number }> = {
  "g-13": { lat: 33.6844, lng: 73.0479 },
  "g-11": { lat: 33.6938, lng: 73.0551 },
  "g-10": { lat: 33.6952, lng: 73.0621 },
  "g-9":  { lat: 33.6987, lng: 73.0667 },
  "g-14": { lat: 33.6699, lng: 73.0342 },
  "g-15": { lat: 33.6601, lng: 73.0219 },
  "g-16": { lat: 33.6560, lng: 73.0142 },
  "f-10": { lat: 33.7025, lng: 73.0122 },
  "f-11": { lat: 33.7098, lng: 73.0229 },
  "f-7":  { lat: 33.7196, lng: 73.0551 },
  "f-8":  { lat: 33.7156, lng: 73.0449 },
  "f-6":  { lat: 33.7282, lng: 73.0618 },
  "e-11": { lat: 33.7290, lng: 73.0130 },
  "e-7":  { lat: 33.7391, lng: 73.0551 },
  "i-8":  { lat: 33.6715, lng: 73.0837 },
  "i-10": { lat: 33.6741, lng: 73.0721 },
  "i-11": { lat: 33.6767, lng: 73.0630 },
  "b-17": { lat: 33.7595, lng: 72.9872 },
  "dha phase 2": { lat: 33.5412, lng: 73.1189 },
  "dha":  { lat: 33.5355, lng: 73.1218 },
  "islamabad": { lat: 33.6938, lng: 73.0551 },
  "rawalpindi": { lat: 33.5651, lng: 73.0169 },
};

// In-memory geocode cache — persists for the lifetime of the server process
const _geocodeCache: Record<string, { lat: number; lng: number }> = {};

// Normalize a location key: lowercase, collapse hyphens/spaces so "f7", "f-7", "f 7" all match
function _normalise(s: string): string {
  return s.toLowerCase().replace(/[\s\-.]/g, "");
}

export async function geocodeLocation(location: string): Promise<{ lat: number; lng: number }> {
  const cacheKey = location.toLowerCase().trim();
  if (_geocodeCache[cacheKey]) return _geocodeCache[cacheKey];

  // Fast static lookup first (normalised comparison)
  const normInput = _normalise(location);
  for (const [area, coords] of Object.entries(_staticCoords)) {
    if (normInput.includes(_normalise(area)) || _normalise(area).includes(normInput)) {
      _geocodeCache[cacheKey] = coords;
      return coords;
    }
  }

  // Nominatim geocoding (free, no API key)
  try {
    const query = location.toLowerCase().includes("pakistan")
      ? location
      : `${location}, Pakistan`;
    const url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(query)}&format=json&limit=1`;
    const res = await fetch(url, {
      headers: { "User-Agent": "HaazirApp/1.0 (haazir-platform)" },
    });
    const data = await res.json() as Array<{ lat: string; lon: string }>;
    if (data.length > 0) {
      const coords = { lat: parseFloat(data[0].lat), lng: parseFloat(data[0].lon) };
      console.log(`[Geocode] "${location}" → (${coords.lat.toFixed(4)}, ${coords.lng.toFixed(4)})`);
      _geocodeCache[cacheKey] = coords;
      return coords;
    }
  } catch (err) {
    console.warn(`[Geocode] Nominatim failed for "${location}":`, err);
  }

  // Final fallback: Islamabad centre
  const fallback = { lat: 33.6844, lng: 73.0479 };
  _geocodeCache[cacheKey] = fallback;
  return fallback;
}

export async function matchProviders(intent: ParsedIntent, excludedIds: string[] = []): Promise<MatchResult> {
  const tStart = Date.now();
  const providersData = getProvidersData();
  const userCoords = await geocodeLocation(intent.location);

  // Real-time capacity and per-provider next-available-slot data
  const liveActiveCounts = getLiveActiveBookingCounts();
  const requestedMs = parseNaturalLanguageTime(intent.preferred_time).getTime();
  const bookedSlots  = buildBookedSlotsMap();

  // STEP 2 - Provider Matching Filters
  let eligible = providersData.filter((p: any) => {
    const pId = p.provider_id || p.id;
    if (excludedIds.includes(pId)) return false;

    const isOnline = p.availability_status === "online";
    const liveJobs = liveActiveCounts[pId] ?? p.active_jobs;
    const capacityOk = liveJobs < p.capacity;
    const matchesService = matchesServiceType(p.service_expertise, intent.service_type);
    const notBlacklisted = (p.cancellation_risk ?? 0) <= 0.30;
    const notInCooldown = !p.cooldown_until || new Date() > new Date(p.cooldown_until);

    // Compute next available slot — providers available within MAX_WAIT_MS pass
    const nextSlot  = getNextAvailableSlotMs(pId, requestedMs, bookedSlots);
    const delay     = nextSlot - requestedMs;
    const withinWait = delay <= MAX_WAIT_MS;

    return isOnline && capacityOk && matchesService && notBlacklisted && notInCooldown && withinWait;
  }).map((p: any) => {
    const pId = p.provider_id || p.id;
    const nextSlot    = getNextAvailableSlotMs(pId, requestedMs, bookedSlots);
    const slotDelayMin = Math.round((nextSlot - requestedMs) / 60000);
    return { ...p, next_available_slot_ms: nextSlot, slot_delay_min: slotDelayMin };
  });

  let fallback_used = false;
  let fallback_reason: string | undefined;

  // Waitlist Fallback if fewer than 3 qualify:
  // Fill with offline or over-capacity matching providers and flag them.
  let isWaitlistedIncluded = false;
  if (eligible.length < 3) {
    fallback_used = true;
    fallback_reason = "Fewer than 3 active online providers found. Filling with waitlisted/offline options.";
    const extraProviders = providersData.filter((p: any) => {
      const pId = p.provider_id || p.id;
      if (excludedIds.includes(pId)) return false;
      const isAlreadyIncluded = eligible.some((e: any) => (e.provider_id || e.id) === pId);
      return !isAlreadyIncluded && matchesServiceType(p.service_expertise, intent.service_type);
    });

    // Mark them as waitlisted and append
    const waitlistedAdded = extraProviders.map((ep: any) => ({
      ...ep,
      is_waitlisted: true,
    }));
    eligible = [...eligible, ...waitlistedAdded];
    isWaitlistedIncluded = true;
  }

  if (eligible.length === 0) {
    const requestedFmt = new Date(requestedMs).toLocaleString("en-US", {
      timeZone: "Asia/Karachi", weekday: "short", month: "short", day: "numeric",
      hour: "numeric", minute: "2-digit", hour12: true,
    });
    return {
      top_providers: [],
      reasoning: `Is waqt ${intent.service_type} ke liye koi provider available nahi hai.`,
      fallback_used: true,
      fallback_reason: `no_providers_at_time:${requestedFmt}`,
      matching_trace: "0 eligible providers within 4h of requested time.",
    };
  }

  // Find min and max rates among eligible to score Price Fit
  const rates = eligible.map((p: any) => p.charges.base_rate);
  const minRate = rates.length > 0 ? Math.min(...rates) : 400;
  const maxRate = rates.length > 0 ? Math.max(...rates) : 1500;
  const rateRange = maxRate - minRate || 100;

  // Score each provider using 8-factor system
  const scored: RankedProvider[] = eligible.map((p: any) => {
    const distance = haversine(userCoords.lat, userCoords.lng, p.location.latitude, p.location.longitude);

    // 1. Travel Time (15%): Score = 100 - (travel_mins / 60 * 100), preferring under 20 mins (10km)
    const travel_mins = distance * 2; // assume 2 mins/km
    const travel_time_score = Math.max(0, 100 - (travel_mins / 60) * 100);

    // 2. Availability Match (15%): exact = 100, delayed = scaled down, waitlisted = 40
    const delayMin = p.slot_delay_min ?? 0;
    let availability_match_score = delayMin === 0 ? 100 : Math.max(0, 100 - (delayMin / (MAX_WAIT_MS / 60000)) * 60);
    if (p.is_waitlisted) {
      availability_match_score = 40; // Penalty since offline/waitlisted
    }

    // 3. Specialization (20%): Exact = 100, Alias/Related = 60, Generic = 30
    const exactMatch  = p.service_expertise.some((s: string) => s.toLowerCase() === intent.service_type.toLowerCase());
    const aliasMatch  = !exactMatch && matchesServiceType(p.service_expertise, intent.service_type);
    const specialization_score = exactMatch ? 100 : aliasMatch ? 60 : 30;

    // 4. On-Time + Reliability (15%): Use live reliability_score if present, else on_time_score
    // reliability_score is a 0–100 EWMA composite — it captures recency better than static on_time_score
    const liveReliability = p.reliability_score != null
      ? p.reliability_score          // already 0–100
      : (p.on_time_score || 0.9) * 100;
    const on_time_score = liveReliability;

    // 5. Review Sentiment (10%): rating-based sentiment + 20% penalty if recent negative spike (rating < 4.3)
    let review_sentiment_score = (p.rating / 5) * 100;
    if (p.rating < 4.3) {
      review_sentiment_score *= 0.8; // 20% penalty
    }

    // 6. Rate (10%): Lower rate scores higher for low budgets; reduce weight to 5% for flexible budgets
    const budgetIsFlexible = intent.budget_sensitivity === "flexible";
    const rate_score = ((maxRate - p.charges.base_rate) / rateRange) * 100;

    // Weights Adjustment
    const wRate = budgetIsFlexible ? 0.05 : 0.10;
    const wSpec = budgetIsFlexible ? 0.25 : 0.20; // Reallocate weight to Specialization

    // 7. Cancellation Risk (10%): (1 - cancellation_risk) * 100
    const cancellation_risk_score = (1 - (p.cancellation_risk || 0)) * 100;

    // 8. Capacity (5%): (capacity - active_jobs) / capacity * 100
    const capacity_score = p.capacity > 0 ? ((p.capacity - p.active_jobs) / p.capacity) * 100 : 100;

    // Weighted Score
    const totalScore =
      0.15 * travel_time_score +
      0.15 * availability_match_score +
      wSpec * specialization_score +
      0.15 * on_time_score +
      0.10 * review_sentiment_score +
      wRate * rate_score +
      0.10 * cancellation_risk_score +
      0.05 * capacity_score;

    return {
      provider_id: p.provider_id,
      name: p.name,
      shop_name: p.shop_name,
      location: p.location,
      city: p.city,
      city_area: p.city_area,
      availability_status: p.availability_status,
      charges: p.charges,
      job_role: p.job_role,
      service_expertise: p.service_expertise,
      rating: p.rating,
      on_time_score: p.on_time_score,
      cancellation_risk: p.cancellation_risk,
      capacity: p.capacity,
      active_jobs: p.active_jobs,
      total_reviews: p.total_reviews,
      total_jobs: p.total_jobs,
      distance_km: Math.round(distance * 10) / 10,
      score: Math.round(totalScore * 100) / 100,
      reliability_score: p.reliability_score != null ? p.reliability_score : Math.round(computeScore(p) * 10) / 10,
      completion_rate: p.completion_rate ?? null,
      score_breakdown: {
        travel_time: Math.round(travel_time_score),
        availability_match: Math.round(availability_match_score),
        specialization: Math.round(specialization_score),
        on_time: Math.round(on_time_score),
        review_sentiment: Math.round(review_sentiment_score),
        rate: Math.round(rate_score),
        cancellation_risk: Math.round(cancellation_risk_score),
        capacity: Math.round(capacity_score),
      },
      is_waitlisted: p.is_waitlisted || false,
    };
  });

  // TIEBREAKER logic: sort primarily by score descending.
  // If scores are within 3 points of each other, apply:
  // 1. Higher on_time_score
  // 2. More recent positive review (represented by higher rating here)
  // 3. Lower cancellation_risk
  const sorted = scored.sort((a, b) => b.score - a.score);

  const top3 = sorted.slice(0, 3);

  // Generate Reasoning — explain the key trade-off (specialization vs proximity etc.)
  let reasoning = "";
  try {
    const isRecommendedFarther = top3.length > 1 && top3[0].distance_km > top3[1].distance_km;
    const budgetNote = intent.budget_sensitivity === "low"
      ? " The customer is price-sensitive — note if this is cost-effective."
      : "";
    const langNote = intent.language === "english" ? "English" : "Urdu / Roman Urdu";

    const reasoningPrompt = `You are Haazir's AI recommendation engine. Write exactly 2 sentences in ${langNote} explaining why ${top3[0].name} is the best match for this request.

Recommended: ${top3[0].name} | ${top3[0].distance_km}km away | ${top3[0].rating}★ | ${Math.round(top3[0].on_time_score * 100)}% on-time | Specialization: ${top3[0].score_breakdown.specialization}/100 | Score: ${top3[0].score}%
${top3[1] ? `Runner-up: ${top3[1].name} | ${top3[1].distance_km}km | ${top3[1].rating}★ | Score: ${top3[1].score}%` : ""}

Context: ${intent.service_type} request | Urgency: ${intent.urgency} | Complexity: ${intent.job_complexity_hint}${budgetNote}
${isRecommendedFarther ? `Key trade-off: ${top3[1]?.name ?? "another provider"} is closer but ${top3[0].name} was chosen for superior specialization and reliability.` : ""}

Be conversational and specific. Mention the deciding factor. No markdown.`;

    const genAI = new GoogleGenerativeAI(process.env.GOOGLE_API_KEY!);
    const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });
    const response = await model.generateContent(reasoningPrompt);
    reasoning = response.response.text().trim();
  } catch {
    reasoning = `${top3[0].name} selected: score ${top3[0].score}%, ${top3[0].distance_km}km away, ${Math.round(top3[0].on_time_score * 100)}% on-time reliability.`;
  }

  const trace = `Matched ${eligible.length} eligible providers using 8 weighted factors and tiebreaker rules. Top Match: ${top3[0]?.name}`;
  const result: MatchResult = {
    top_providers: top3,
    reasoning,
    fallback_used,
    fallback_reason,
    matching_trace: trace,
  };
  logProviderMatch(intent, result, Date.now() - tStart);
  return result;
}
