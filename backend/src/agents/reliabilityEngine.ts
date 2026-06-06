// Provider Reliability Score Engine
// EWMA-based live score that replaces static on_time_score + cancellation_risk in the matcher.
//
// Formula (0–100):
//   30 × on_time_rate (EWMA)
// + 25 × completion_rate (EWMA)
// + 20 × recency_weighted_rating   (rating / 5)
// + 15 × (1 − cancellation_rate EWMA)
// + 10 × dispute_outcome_factor
//
// EWMA: new_value = 0.3 × latest_event + 0.7 × previous_value

import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const providersFile = path.join(__dirname, "../../data/mock_providers.json");
const ledgerFile    = path.join(__dirname, "../../data/mock_reliability_ledger.json");

export type ReliabilityEvent =
  | "cancel_after_accept"   // −large
  | "no_show"               // −severe
  | "late_arrival"          // −medium
  | "dispute_lost_severe"   // −large
  | "job_completed_ontime"  // +small
  | "job_completed_late"    // neutral → small positive
  | "dispute_won";          // +small

const EVENT_DELTAS: Record<ReliabilityEvent, number> = {
  cancel_after_accept:  -15,
  no_show:              -25,
  late_arrival:         -6,
  dispute_lost_severe:  -12,
  job_completed_ontime: +3,
  job_completed_late:   +1,
  dispute_won:          +4,
};

const EWMA_ALPHA = 0.3; // weight of latest event

function ewma(previous: number, latestBinary: number): number {
  return EWMA_ALPHA * latestBinary + (1 - EWMA_ALPHA) * previous;
}

function readProviders(): any[] {
  try { return JSON.parse(fs.readFileSync(providersFile, "utf-8")); }
  catch { return []; }
}

function writeProviders(data: any[]): void {
  fs.writeFileSync(providersFile, JSON.stringify(data, null, 2));
}

function readLedger(): any[] {
  try {
    if (!fs.existsSync(ledgerFile)) return [];
    return JSON.parse(fs.readFileSync(ledgerFile, "utf-8"));
  } catch { return []; }
}

function writeLedger(data: any[]): void {
  fs.writeFileSync(ledgerFile, JSON.stringify(data, null, 2));
}

export function computeScore(provider: any): number {
  const onTime      = (provider.on_time_score ?? 0.85) * 100;
  const completion  = (provider.completion_rate ?? 0.90) * 100;
  const rating      = (provider.rating ?? 4.0) / 5 * 100;
  const noCancel    = (1 - (provider.cancellation_risk ?? 0.1)) * 100;
  const disputes    = provider.dispute_outcomes ?? { won: 0, lost: 0 };
  const total       = disputes.won + disputes.lost;
  const disputeFactor = total === 0 ? 80 : (disputes.won / total) * 100;

  return Math.max(0, Math.min(100,
    0.30 * onTime +
    0.25 * completion +
    0.20 * rating +
    0.15 * noCancel +
    0.10 * disputeFactor
  ));
}

export function applyEvent(
  providerId: string,
  event: ReliabilityEvent,
  bookingId?: string
): { new_score: number; delta: number; cooldown: boolean } | null {
  const providers = readProviders();
  const idx = providers.findIndex((p: any) => p.provider_id === providerId);
  if (idx === -1) return null;

  const p = providers[idx];
  const delta = EVENT_DELTAS[event];

  // EWMA updates per event type
  if (event === "cancel_after_accept") {
    p.cancellation_risk = Math.min(0.99, ewma(p.cancellation_risk ?? 0.1, 1));
  } else if (event === "no_show") {
    p.cancellation_risk = Math.min(0.99, ewma(p.cancellation_risk ?? 0.1, 1));
    p.no_show_count = (p.no_show_count ?? 0) + 1;
  } else if (event === "late_arrival") {
    p.on_time_score = Math.max(0, ewma(p.on_time_score ?? 0.85, 0));
  } else if (event === "job_completed_ontime") {
    p.on_time_score    = Math.min(1, ewma(p.on_time_score ?? 0.85, 1));
    p.completion_rate  = Math.min(1, ewma(p.completion_rate ?? 0.90, 1));
    p.cancellation_risk = Math.max(0, ewma(p.cancellation_risk ?? 0.1, 0) * 0.97);
  } else if (event === "job_completed_late") {
    p.completion_rate = Math.min(1, ewma(p.completion_rate ?? 0.90, 1));
  } else if (event === "dispute_lost_severe") {
    const d = p.dispute_outcomes ?? { won: 0, lost: 0 };
    p.dispute_outcomes = { won: d.won, lost: d.lost + 1 };
  } else if (event === "dispute_won") {
    const d = p.dispute_outcomes ?? { won: 0, lost: 0 };
    p.dispute_outcomes = { won: d.won + 1, lost: d.lost };
  }

  const newScore = computeScore(p);
  p.reliability_score = Math.round(newScore * 10) / 10;

  // Auto-cooldown: score < 40 or ≥2 no-shows
  const cooldown = newScore < 40 || (p.no_show_count ?? 0) >= 2;
  if (cooldown) {
    p.availability_status = "offline";
    p.cooldown_until = new Date(Date.now() + 4 * 3600_000).toISOString(); // 4h
  }

  providers[idx] = p;
  writeProviders(providers);

  // Append ledger entry
  const ledger = readLedger();
  ledger.push({
    provider_id: providerId,
    event,
    delta,
    reason: event.replace(/_/g, " "),
    booking_id: bookingId ?? null,
    new_score: p.reliability_score,
    ts: new Date().toISOString(),
  });
  writeLedger(ledger);

  return { new_score: p.reliability_score, delta, cooldown };
}

export function getReliabilitySnapshot(providerId: string): {
  score: number;
  ledger: any[];
} | null {
  const providers = readProviders();
  const p = providers.find((x: any) => x.provider_id === providerId);
  if (!p) return null;

  if (p.reliability_score == null) {
    p.reliability_score = Math.round(computeScore(p) * 10) / 10;
  }

  const ledger = readLedger().filter((e: any) => e.provider_id === providerId).slice(-10);
  return { score: p.reliability_score, ledger };
}

export function applyDisputeOutcome(
  providerId: string,
  outcome: "won" | "lost",
  bookingId?: string
): void {
  applyEvent(
    providerId,
    outcome === "lost" ? "dispute_lost_severe" : "dispute_won",
    bookingId
  );
}
