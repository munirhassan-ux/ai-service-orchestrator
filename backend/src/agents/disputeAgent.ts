// Dispute Resolution Agent — evidence-grounded, data-driven, no he-said-she-said.
// Evidence assembled from contract, state_history, GPS log, checklist, price breakdown, A2A cfp_log.
// Gemini reasons over evidence vs policy. Auto-resolves if confidence ≥ threshold.

import { GoogleGenerativeAI } from "@google/generative-ai";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { applyDisputeOutcome } from "./reliabilityEngine.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const disputesFile  = path.join(__dirname, "../../data/mock_disputes.json");
const bookingsFile  = path.join(__dirname, "../../data/mock_bookings.json");
const contractsFile = path.join(__dirname, "../../data/mock_contracts.json");

export type DisputeType = "overcharge" | "no_show" | "late_arrival" | "poor_quality" | "price_dispute" | "quality_complaint" | "cancellation";
export type DisputeStatus = "proposed" | "accepted" | "rejected" | "escalated" | "resolved" | "awaiting_completion";

export interface DisputeRecord {
  dispute_id: string;
  booking_id: string;
  contract_id: string | null;
  provider_id: string;
  type: DisputeType;
  raised_by: "customer";
  evidence: Record<string, any>;
  agent_reasoning: string;
  proposed_action: string;
  confidence: number;
  status: DisputeStatus;
  reliability_impact: number;
  needs_recovery?: boolean;
  created_at: string;
  resolved_at?: string;
}

function readDisputes(): DisputeRecord[] {
  try {
    if (!fs.existsSync(disputesFile)) return [];
    return JSON.parse(fs.readFileSync(disputesFile, "utf-8"));
  } catch { return []; }
}

function writeDisputes(data: DisputeRecord[]): void {
  fs.writeFileSync(disputesFile, JSON.stringify(data, null, 2));
}

function readBooking(bookingId: string): any | null {
  try {
    const data = JSON.parse(fs.readFileSync(bookingsFile, "utf-8"));
    return data.bookings?.find((b: any) => b.booking_id === bookingId) ?? null;
  } catch { return null; }
}

function writeDisputeIdToBooking(bookingId: string, disputeId: string): void {
  try {
    const raw = JSON.parse(fs.readFileSync(bookingsFile, "utf-8"));
    const idx = raw.bookings?.findIndex((b: any) => b.booking_id === bookingId) ?? -1;
    if (idx === -1) return;
    raw.bookings[idx].dispute_id = disputeId;
    fs.writeFileSync(bookingsFile, JSON.stringify(raw, null, 2));
  } catch { /* non-fatal */ }
}

function appendAgentMessageToBooking(bookingId: string, message: any): void {
  try {
    const raw = JSON.parse(fs.readFileSync(bookingsFile, "utf-8"));
    const idx = raw.bookings?.findIndex((b: any) => b.booking_id === bookingId) ?? -1;
    if (idx === -1) return;
    if (!raw.bookings[idx].agent_messages) raw.bookings[idx].agent_messages = [];
    raw.bookings[idx].agent_messages.push(message);
    fs.writeFileSync(bookingsFile, JSON.stringify(raw, null, 2));
  } catch { /* non-fatal */ }
}

function readContract(contractId: string): any | null {
  try {
    if (!fs.existsSync(contractsFile)) return null;
    const data: any[] = JSON.parse(fs.readFileSync(contractsFile, "utf-8"));
    return data.find(c => c.contract_id === contractId) ?? null;
  } catch { return null; }
}

function assembleEvidence(booking: any, contract: any | null, type: DisputeType): Record<string, any> {
  const arrivedEntry = booking.state_history?.find((h: any) => h.status === "ARRIVED");
  const inProgressEntry = booking.state_history?.find((h: any) => h.status === "IN_PROGRESS");
  const checklist = booking.checklist ?? [];
  const completedItems = checklist.filter((i: any) => i.completed).length;

  const evidence: Record<string, any> = {
    booking_id:         booking.booking_id,
    service_type:       booking.service_type,
    booking_status:     booking.status,
    scheduled_time:     booking.scheduled_time ?? null,
    is_future_scheduled: booking.status === "SCHEDULED" && booking.scheduled_time
      ? new Date(booking.scheduled_time).getTime() > Date.now()
      : false,
    minutes_past_scheduled: booking.scheduled_time
      ? Math.round((Date.now() - new Date(booking.scheduled_time).getTime()) / 60000)
      : null,
    final_price:        booking.final_price,
    agreed_price:       contract?.agreed_price ?? booking.final_price,
    overcharge_amount:  (booking.final_price ?? 0) - (contract?.agreed_price ?? booking.final_price ?? 0),
    state_history:      booking.state_history ?? [],
    arrived_timestamp:  arrivedEntry?.timestamp ?? null,
    promised_eta_min:   contract ? (() => {
      const bid = contract.cfp_log?.find((b: any) => b.provider_id === booking.provider_id);
      return bid?.eta_min ?? null;
    })() : null,
    checklist_total:    checklist.length,
    checklist_completed: completedItems,
    checklist_completion_pct: checklist.length > 0 ? Math.round(completedItems / checklist.length * 100) : 0,
    cfp_log:            contract?.cfp_log ?? null,
  };

  // Type-specific additions
  if (type === "no_show") {
    evidence.reached_arrived = !!arrivedEntry;
    evidence.reached_in_progress = !!inProgressEntry;
  }
  if (type === "late_arrival" && arrivedEntry && booking.scheduled_time) {
    const scheduledMs = new Date(booking.scheduled_time).getTime();
    const arrivedMs   = new Date(arrivedEntry.timestamp).getTime();
    evidence.late_by_minutes = Math.round((arrivedMs - scheduledMs) / 60000);
  }

  return evidence;
}

function ruleBasedResolution(
  type: DisputeType,
  evidence: Record<string, any>
): { proposed_action: string; confidence: number; reasoning: string; reliability_impact: number } {
  switch (type) {
    case "no_show": {
      // Booking hasn't happened yet — scheduled for the future
      if (evidence.is_future_scheduled && evidence.scheduled_time) {
        const scheduledDate = new Date(evidence.scheduled_time);
        const dateStr = scheduledDate.toLocaleDateString("en-PK", {
          weekday: "long", year: "numeric", month: "long", day: "numeric",
          hour: "2-digit", minute: "2-digit",
        });
        return { proposed_action: "dismiss", confidence: 0.97,
          reasoning: `No-show cannot be confirmed — this booking is scheduled for ${dateStr}. The provider has not missed the appointment yet.`,
          reliability_impact: 0 };
      }
      if (!evidence.reached_arrived) {
        return { proposed_action: "full_refund", confidence: 0.90,
          reasoning: "Provider never reached ARRIVED status — clear no-show confirmed by state history.",
          reliability_impact: -10 };
      }
      return { proposed_action: "provider_warning", confidence: 0.60,
        reasoning: "Provider did arrive but no-show dispute raised — escalating for review.",
        reliability_impact: -4 };
    }

    case "late_arrival": {
      const late = evidence.late_by_minutes ?? 0;
      if (late <= 0) {
        const early = -late;
        return { proposed_action: "dismiss", confidence: 0.95,
          reasoning: early > 0
            ? `Provider arrived ${early} minutes early — no late arrival occurred.`
            : `Provider arrived exactly on time — late arrival claim dismissed.`,
          reliability_impact: 0 };
      }
      if (late > 60) return { proposed_action: "partial_refund_150", confidence: 0.82,
        reasoning: `Provider arrived ${late} minutes late — exceeds 60-minute policy threshold.`,
        reliability_impact: -6 };
      if (late > 30) return { proposed_action: "service_credit_150", confidence: 0.78,
        reasoning: `Provider arrived ${late} minutes late — exceeds 30-minute threshold, service credit applied.`,
        reliability_impact: -4 };
      return { proposed_action: "dismiss", confidence: 0.70,
        reasoning: `Provider arrived ${late} minutes late — within acceptable tolerance.`,
        reliability_impact: -1 };
    }

    case "overcharge": {
      const over = evidence.overcharge_amount ?? 0;
      if (over > 0 && evidence.checklist_completion_pct === 100) {
        return { proposed_action: `partial_refund_${over}`, confidence: 0.88,
          reasoning: `Charged Rs.${evidence.final_price} vs agreed Rs.${evidence.agreed_price} — refunding overcharge of Rs.${over}.`,
          reliability_impact: -5 };
      }
      return { proposed_action: "dismiss", confidence: 0.65,
        reasoning: "Final price within agreed range or work was incomplete — no overcharge confirmed.",
        reliability_impact: 0 };
    }

    case "poor_quality":
    case "quality_complaint": {
      const pct = evidence.checklist_completion_pct ?? 100;
      if (pct < 50) return { proposed_action: "redo_at_no_cost", confidence: 0.80,
        reasoning: `Only ${pct}% of checklist completed — substantial rework required.`,
        reliability_impact: -8 };
      if (pct < 75) return { proposed_action: "partial_refund_200", confidence: 0.72,
        reasoning: `${pct}% checklist completion — below quality threshold, partial refund applied.`,
        reliability_impact: -5 };
      return { proposed_action: "provider_warning", confidence: 0.55,
        reasoning: `${pct}% checklist completion — quality concern noted, escalating for review.`,
        reliability_impact: -2 };
    }

    default:
      return { proposed_action: "escalate", confidence: 0.50,
        reasoning: "Dispute type requires human review.",
        reliability_impact: 0 };
  }
}

async function reasonWithGemini(
  type: DisputeType,
  evidence: Record<string, any>,
  customerComment: string
): Promise<{ proposed_action: string; confidence: number; reasoning: string; reliability_impact: number }> {
  try {
    const genAI = new GoogleGenerativeAI(process.env.GOOGLE_API_KEY!);
    const model = genAI.getGenerativeModel({
      model: "gemini-2.0-flash",
      generationConfig: { responseMimeType: "application/json" },
    });

    const prompt = `You are Haazir's DisputeAgent. Reason over the evidence below and propose a resolution.

Dispute type: ${type}
Customer comment: "${customerComment}"
Evidence: ${JSON.stringify(evidence, null, 2)}

Resolution options: full_refund | partial_refund_N (N = PKR amount) | service_credit_N | provider_warning | reliability_penalty | dismiss | redo_at_no_cost

Rules:
- overcharge: if overcharge_amount > 0 and checklist_completion_pct = 100, propose partial_refund for the overcharge amount.
- no_show: if is_future_scheduled is true, propose dismiss — the booking is scheduled for a future date, the provider has not missed it yet. Include the scheduled_time in your reasoning.
- no_show: if is_future_scheduled is false and reached_arrived is false, propose full_refund.
- late_arrival: if late_by_minutes <= 0, the provider arrived early or on time — dismiss. If > 30, propose service_credit_150; if > 60, propose partial_refund_150. Never show negative minutes in reasoning; convert to "X minutes early".
- poor_quality/quality_complaint: if checklist_completion_pct < 75, propose redo_at_no_cost or partial_refund.
- If evidence is ambiguous, lower confidence (< 0.65) and propose escalate.

Return JSON:
{
  "proposed_action": "string (e.g. partial_refund_400)",
  "confidence": float 0–1,
  "reasoning": "one clear sentence citing specific evidence values",
  "reliability_impact": integer (negative = penalty, e.g. -8)
}`;

    const result = await model.generateContent(prompt);
    return JSON.parse(result.response.text().replace(/```json|```/g, "").trim());
  } catch (err: any) {
    console.warn(`[DisputeAgent] Gemini unavailable (${err?.message?.slice(0, 60) ?? "unknown"}), using rule-based fallback`);
    return ruleBasedResolution(type, evidence);
  }
}

export async function raiseDispute(
  bookingId: string,
  type: DisputeType,
  customerComment: string
): Promise<DisputeRecord> {
  const booking = readBooking(bookingId);
  if (!booking) throw new Error(`Booking ${bookingId} not found`);

  const contract = booking.contract_id ? readContract(booking.contract_id) : null;
  const evidence = assembleEvidence(booking, contract, type);

  // Booking is still live (provider on-site or job underway) — cannot resolve yet
  const inProgressStatuses = ["ARRIVED", "IN_PROGRESS"];
  if (inProgressStatuses.includes(booking.status)) {
    const dispute: DisputeRecord = {
      dispute_id:        `DSP-${Date.now()}`,
      booking_id:        bookingId,
      contract_id:       booking.contract_id ?? null,
      provider_id:       booking.provider_id,
      type,
      raised_by:         "customer",
      evidence,
      agent_reasoning:   "Dispute logged. Resolution will be determined once the job is completed or cancelled.",
      proposed_action:   "awaiting_job_completion",
      confidence:        1.0,
      status:            "awaiting_completion",
      reliability_impact: 0,
      created_at:        new Date().toISOString(),
    };
    const disputes = readDisputes();
    disputes.push(dispute);
    writeDisputes(disputes);
    writeDisputeIdToBooking(bookingId, dispute.dispute_id);
    return dispute;
  }

  // No-show confirmed: booking time has passed by 5+ min and provider never arrived
  const noShowConfirmed =
    type === "no_show" &&
    !evidence.is_future_scheduled &&
    !evidence.reached_arrived &&
    !["COMPLETED", "CANCELLED_PROVIDER", "CANCELLED_TIMEOUT", "CANCELLED_CUSTOMER"].includes(booking.status) &&
    (evidence.minutes_past_scheduled ?? 0) >= 5;

  const geminiResult = await reasonWithGemini(type, evidence, customerComment);

  let finalStatus: DisputeStatus;
  let needsRecovery = false;

  if (noShowConfirmed) {
    finalStatus  = "resolved";
    needsRecovery = true;
  } else {
    finalStatus = geminiResult.confidence >= 0.65 ? "proposed" : "escalated";
  }

  const dispute: DisputeRecord = {
    dispute_id:        `DSP-${Date.now()}`,
    booking_id:        bookingId,
    contract_id:       booking.contract_id ?? null,
    provider_id:       booking.provider_id,
    type,
    raised_by:         "customer",
    evidence,
    agent_reasoning:   geminiResult.reasoning,
    proposed_action:   geminiResult.proposed_action,
    confidence:        geminiResult.confidence,
    status:            finalStatus,
    reliability_impact: geminiResult.reliability_impact,
    needs_recovery:    needsRecovery || undefined,
    created_at:        new Date().toISOString(),
  };

  const disputes = readDisputes();
  disputes.push(dispute);
  writeDisputes(disputes);
  writeDisputeIdToBooking(bookingId, dispute.dispute_id);

  return dispute;
}

// Called when a booking reaches a terminal state (COMPLETED / CANCELLED_*)
// so disputes that were "awaiting_completion" can be resolved.
export async function resolveAwaitingDisputes(bookingId: string): Promise<void> {
  const disputes = readDisputes();
  const pending = disputes.filter(
    d => d.booking_id === bookingId && d.status === "awaiting_completion"
  );
  if (pending.length === 0) return;

  const booking = readBooking(bookingId);
  if (!booking) return;

  const contract = booking.contract_id ? readContract(booking.contract_id) : null;

  for (const d of pending) {
    try {
      const evidence   = assembleEvidence(booking, contract, d.type);
      const resolution = await reasonWithGemini(d.type, evidence, "");
      d.evidence          = evidence;  // refresh with final booking state
      d.agent_reasoning   = resolution.reasoning;
      d.proposed_action   = resolution.proposed_action;
      d.confidence        = resolution.confidence;
      d.status            = resolution.confidence >= 0.65 ? "proposed" : "escalated";
      d.reliability_impact = resolution.reliability_impact;
      d.resolved_at       = new Date().toISOString();
      console.log(`[DisputeAgent] Resolved awaiting dispute ${d.dispute_id} → ${d.proposed_action}`);
    } catch (err: any) {
      console.error(`[DisputeAgent] Failed to resolve ${d.dispute_id}: ${err.message}`);
    }
  }

  const updated = disputes.map(d => {
    const match = pending.find(p => p.dispute_id === d.dispute_id);
    return match ?? d;
  });
  writeDisputes(updated);
}

export function getDispute(disputeId: string): DisputeRecord | undefined {
  return readDisputes().find(d => d.dispute_id === disputeId);
}

export function listDisputes(bookingId?: string): DisputeRecord[] {
  const all = readDisputes();
  return bookingId ? all.filter(d => d.booking_id === bookingId) : all;
}

export async function respondToDispute(
  disputeId: string,
  party: "customer" | "provider",
  decision: "accept" | "reject"
): Promise<DisputeRecord> {
  const disputes = readDisputes();
  const idx = disputes.findIndex(d => d.dispute_id === disputeId);
  if (idx === -1) throw new Error(`Dispute ${disputeId} not found`);

  const dispute = disputes[idx];

  if (decision === "accept") {
    dispute.status = "resolved";
    dispute.resolved_at = new Date().toISOString();
    if (dispute.reliability_impact < 0) {
      applyDisputeOutcome(dispute.provider_id, "lost", dispute.booking_id);
    } else {
      applyDisputeOutcome(dispute.provider_id, "won", dispute.booking_id);
    }
    appendAgentMessageToBooking(dispute.booking_id, {
      from: "dispute_agent",
      to: "customer_agent",
      status: "DISPUTE_RESOLVED",
      message: `Dispute accepted. Resolution: ${dispute.proposed_action.replace(/_/g, " ")}. ${dispute.agent_reasoning}`,
      timestamp: new Date().toISOString(),
    });
  } else {
    dispute.status = "escalated";
    appendAgentMessageToBooking(dispute.booking_id, {
      from: "dispute_agent",
      to: "customer_agent",
      status: "DISPUTE_ESCALATED",
      message: `Dispute escalated for human review. Our team will follow up within 24 hours.`,
      timestamp: new Date().toISOString(),
    });
  }

  disputes[idx] = dispute;
  writeDisputes(disputes);
  return dispute;
}

// Legacy compatibility — keep old processDispute signature working
export async function processDispute(
  bookingId: string,
  providerId: string,
  issueType: any,
  customerComment: string
) {
  const typeMap: Record<string, DisputeType> = {
    quality_complaint: "poor_quality",
    price_dispute: "overcharge",
    no_show: "no_show",
    cancellation: "cancellation",
  };
  const type: DisputeType = typeMap[issueType] ?? "poor_quality";
  return raiseDispute(bookingId, type, customerComment);
}
