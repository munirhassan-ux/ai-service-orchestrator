import { GoogleGenerativeAI } from "@google/generative-ai";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
import { ParsedIntent } from "./intentParser.js";

const providers = JSON.parse(
  fs.readFileSync(path.join(__dirname, "../../data/mock_providers.json"), "utf-8")
);

export interface RankedProvider {
  id: string;
  name: string;
  service_types: string[];
  skill_level: string;
  rating: number;
  on_time_score: number;
  cancellation_rate: number;
  risk_score: number;
  price_per_hour: number;
  city_area: string;
  available: boolean;
  distance_km: number;
  score: number;
  score_breakdown: {
    proximity: number;
    rating_recency: number;
    on_time: number;
    skill_match: number;
    price_fit: number;
    availability: number;
  };
  next_available_slot?: string;
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

// Area to approximate coordinates (Islamabad areas)
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

function skillLevelValue(level: string): number {
  const map: Record<string, number> = { basic: 1, intermediate: 2, complex: 3 };
  return map[level] || 1;
}

function complexityToSkillRequired(hint: string): number {
  const map: Record<string, number> = { basic: 1, intermediate: 2, complex: 3 };
  return map[hint] || 1;
}

function isBlacklisted(provider: any): boolean {
  return provider.cancellation_rate > 0.3 || provider.risk_score > 0.7;
}

export async function matchProviders(intent: ParsedIntent): Promise<MatchResult> {
  const userCoords = getAreaCoords(intent.location);
  const requiredSkill = complexityToSkillRequired(intent.job_complexity_hint);

  // Filter: service type + not blacklisted + skill level sufficient
  let eligible = providers.filter((p: any) => {
    const hasService = p.service_types.some(
      (s: string) =>
        s === intent.service_type ||
        s.startsWith(intent.service_type.split("_")[0])
    );
    const skillOk = skillLevelValue(p.skill_level) >= requiredSkill;
    return hasService && skillOk && !isBlacklisted(p);
  });

  let fallback_used = false;
  let fallback_reason: string | undefined;

  if (eligible.length === 0) {
    // Fallback: relax skill constraint
    eligible = providers.filter((p: any) => {
      const hasService = p.service_types.some((s: string) =>
        s.startsWith(intent.service_type.split("_")[0])
      );
      return hasService && !isBlacklisted(p);
    });
    fallback_used = true;
    fallback_reason = `No ${intent.job_complexity_hint}-level providers found. Showing all available skill levels.`;
  }

  if (eligible.length === 0) {
    return {
      top_providers: [],
      reasoning: `No providers found for ${intent.service_type} in ${intent.location}.`,
      fallback_used: true,
      fallback_reason: "No providers available for this service in your area.",
      matching_trace: "0 providers matched after all filters.",
    };
  }

  // Score each provider on 6 factors
  const maxDistance = 20;

  const scored: RankedProvider[] = eligible.map((p: any) => {
    const distance = haversine(userCoords.lat, userCoords.lng, p.lat, p.lng);

    // Factor 1: Proximity (0-1, closer = higher)
    const proximityScore = Math.max(0, 1 - distance / maxDistance);

    // Factor 2: Rating + recency (recency decay: older reviews weight less)
    const recencyWeight = Math.max(0.5, 1 - p.review_recency_days / 30);
    const ratingScore = (p.rating / 5) * recencyWeight;

    // Factor 3: On-time score (0-1)
    const onTimeScore = p.on_time_score;

    // Factor 4: Skill match (exact level = 1.0, over-qualified = 0.9, under = 0)
    const providerSkill = skillLevelValue(p.skill_level);
    const skillMatchScore =
      providerSkill === requiredSkill ? 1.0 : providerSkill > requiredSkill ? 0.9 : 0;

    // Factor 5: Price fit (budget sensitive = prefer cheaper, else neutral)
    const avgPrice = 800;
    const priceScore = intent.budget_sensitivity
      ? Math.max(0, 1 - (p.price_per_hour - 400) / 800)
      : 1 - Math.abs(p.price_per_hour - avgPrice) / avgPrice / 2;

    // Factor 6: Availability (available = 1, offline = 0.2)
    const availScore = p.available ? 1.0 : 0.2;

    // Weighted total
    const total =
      0.20 * proximityScore +
      0.20 * ratingScore +
      0.20 * onTimeScore +
      0.15 * skillMatchScore +
      0.15 * priceScore +
      0.10 * availScore;

    return {
      ...p,
      distance_km: Math.round(distance * 10) / 10,
      score: Math.round(total * 100) / 100,
      score_breakdown: {
        proximity: Math.round(proximityScore * 100) / 100,
        rating_recency: Math.round(ratingScore * 100) / 100,
        on_time: Math.round(onTimeScore * 100) / 100,
        skill_match: Math.round(skillMatchScore * 100) / 100,
        price_fit: Math.round(priceScore * 100) / 100,
        availability: availScore,
      },
    };
  });

  // Sort by score descending, take top 3
  const top3 = scored.sort((a, b) => b.score - a.score).slice(0, 3);

  // Generate reasoning using Claude
  const reasoningPrompt = `You are an AI matching agent for a Pakistani home services app.
Explain in 2 sentences (mix of English and Roman Urdu is fine) why ${top3[0]?.name} was selected as the top provider for a ${intent.service_type} job in ${intent.location}.

Top provider score breakdown:
- Proximity: ${top3[0]?.score_breakdown.proximity} (${top3[0]?.distance_km} km away)
- Rating+Recency: ${top3[0]?.score_breakdown.rating_recency} (${top3[0]?.rating}★, last review ${providers.find((p:any)=>p.id===top3[0]?.id)?.review_recency_days} days ago)
- On-time score: ${top3[0]?.score_breakdown.on_time} (${Math.round((top3[0]?.on_time_score || 0) * 100)}%)
- Skill match: ${top3[0]?.score_breakdown.skill_match} (${top3[0]?.skill_level} level)
- Price fit: ${top3[0]?.score_breakdown.price_fit} (Rs. ${top3[0]?.price_per_hour}/hr)
- Total score: ${top3[0]?.score}

Be concise and specific. Mention the key differentiator vs other options.`;

  const genAI = new GoogleGenerativeAI(process.env.GOOGLE_API_KEY!);
  const model = genAI.getGenerativeModel({ 
    model: "gemini-3.1-flash-lite",
    generationConfig: { maxOutputTokens: 200 }
  });

  const reasoningResult = await model.generateContent(reasoningPrompt);
  const reasoningResp = await reasoningResult.response;
  const reasoning = reasoningResp.text().trim() || `${top3[0]?.name} selected based on best combined score for proximity, rating, and reliability.`;

  const trace = `Matched ${eligible.length} eligible providers → scored on 6 factors → top 3 returned. Best: ${top3[0]?.name} (score: ${top3[0]?.score})`;
  console.log(`[ProviderMatcher] ${trace}`);

  return {
    top_providers: top3,
    reasoning,
    fallback_used,
    fallback_reason,
    matching_trace: trace,
  };
}
