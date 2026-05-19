import { GoogleGenerativeAI } from "@google/generative-ai";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
import { ParsedIntent } from "./intentParser.js";

function getProvidersData() {
  const filePath = path.join(__dirname, "../../data/mock_providers.json");
  return JSON.parse(fs.readFileSync(filePath, "utf-8"));
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

const areaCoords: Record<string, { lat: number; lng: number }> = {
  "g-13": { lat: 33.6844, lng: 73.0479 },
  "g-11": { lat: 33.6938, lng: 73.0551 },
  "g-10": { lat: 33.6952, lng: 73.0621 },
  "g-9":  { lat: 33.6987, lng: 73.0667 },
  "g-14": { lat: 33.6699, lng: 73.0342 },
  "g-15": { lat: 33.6601, lng: 73.0219 },
  "f-10": { lat: 33.7025, lng: 73.0122 },
  "f-11": { lat: 33.7098, lng: 73.0229 },
  "f-7":  { lat: 33.7196, lng: 73.0551 },
  "f-8":  { lat: 33.7156, lng: 73.0449 },
  "e-11": { lat: 33.7290, lng: 73.0130 },
  "i-8":  { lat: 33.6715, lng: 73.0837 },
  "i-10": { lat: 33.6741, lng: 73.0721 },
  "b-17": { lat: 33.7595, lng: 72.9872 },
  "dha":  { lat: 33.5355, lng: 73.1218 },
  "dha phase 2": { lat: 33.5412, lng: 73.1189 },
};

function getAreaCoords(location: string): { lat: number; lng: number } {
  const key = location.toLowerCase().trim();
  for (const [area, coords] of Object.entries(areaCoords)) {
    if (key.includes(area) || area.includes(key)) return coords;
  }
  return { lat: 33.6844, lng: 73.0479 }; // Default: G-13
}

export async function matchProviders(intent: ParsedIntent, excludedIds: string[] = []): Promise<MatchResult> {
  const providersData = getProvidersData();
  const userCoords = getAreaCoords(intent.location);

  // STEP 2 - Provider Matching Filters
  // Filter providers who:
  // - Are online
  // - Have active jobs under capacity
  // - Match the service type
  let eligible = providersData.filter((p: any) => {
    const pId = p.provider_id || p.id;
    if (excludedIds.includes(pId)) return false;
    
    const isOnline = p.availability_status === "online";
    const capacityOk = p.active_jobs < p.capacity;
    const matchesService = p.service_expertise.some(
      (s: string) =>
        s.toLowerCase() === intent.service_type.toLowerCase() ||
        s.toLowerCase().startsWith(intent.service_type.toLowerCase().split("_")[0])
    );
    return isOnline && capacityOk && matchesService;
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
      const isAlreadyIncluded = eligible.some((e: any) => e.provider_id === p.provider_id);
      const matchesService = p.service_expertise.some(
        (s: string) =>
          s.toLowerCase() === intent.service_type.toLowerCase() ||
          s.toLowerCase().startsWith(intent.service_type.toLowerCase().split("_")[0])
      );
      return !isAlreadyIncluded && matchesService;
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
    return {
      top_providers: [],
      reasoning: `Hum maazrat chahte hain, is waqt ${intent.service_type} ke liye koi provider available nahi hai.`,
      fallback_used: true,
      fallback_reason: "No providers matched.",
      matching_trace: "0 eligible providers matched.",
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

    // 2. Availability Match (15%): Exact = 100, +/-1hr = 70, +/-2hr = 40
    // We assume slot matches closely unless booked up
    let availability_match_score = 100;
    if (p.is_waitlisted) {
      availability_match_score = 40; // Penalty since offline/waitlisted
    }

    // 3. Specialization (20%): Exact = 100, Related = 60, Generic = 30
    const exactMatch = p.service_expertise.some((s: string) => s.toLowerCase() === intent.service_type.toLowerCase());
    let specialization_score = 30;
    if (exactMatch) {
      specialization_score = 100;
    } else if (p.service_expertise.some((s: string) => s.toLowerCase().startsWith(intent.service_type.toLowerCase().split("_")[0]))) {
      specialization_score = 60;
    }

    // 4. On-Time Score (15%): on_time_score * 100
    const on_time_score = (p.on_time_score || 0.9) * 100;

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
  const sorted = scored.sort((a, b) => {
    const diff = Math.abs(a.score - b.score);
    if (diff <= 3) {
      if (a.on_time_score !== b.on_time_score) {
        return b.on_time_score - a.on_time_score;
      }
      if (a.rating !== b.rating) {
        return b.rating - a.rating;
      }
      return a.cancellation_risk - b.cancellation_risk;
    }
    return b.score - a.score;
  });

  const top3 = sorted.slice(0, 3);

  // Generate Reasoning
  let reasoning = "";
  try {
    const reasoningPrompt = `You are the matching AI for Khedmatgar, a home services platform.
Explain in 2 sentences in Urdu/Roman Urdu why ${top3[0].name} (Score: ${top3[0].score}%, ${top3[0].distance_km}km door) is the best match for ${intent.service_type} in ${intent.location}.
Primary strengths:
- Distance: ${top3[0].distance_km}km
- Rating: ${top3[0].rating}★
- On-Time: ${Math.round(top3[0].on_time_score * 100)}%
- Specialization: Exact matches service.
Be extremely concise.`;

    const genAI = new GoogleGenerativeAI(process.env.GOOGLE_API_KEY!);
    const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });
    const response = await model.generateContent(reasoningPrompt);
    reasoning = response.response.text().trim();
  } catch {
    reasoning = `${top3[0].name} selected based on high composite score of ${top3[0].score}%, proximity of ${top3[0].distance_km}km, and excellent rating.`;
  }

  const trace = `Matched ${eligible.length} eligible providers using 8 weighted factors and tiebreaker rules. Top Match: ${top3[0]?.name}`;
  return {
    top_providers: top3,
    reasoning,
    fallback_used,
    fallback_reason,
    matching_trace: trace,
  };
}
