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
export type DisputeStatus = "proposed" | "accepted" | "rejected" | "escalated" | "resolved";

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

async function reasonWithGemini(
  type: DisputeType,
  evidence: Record<string, any>,
  customerComment: string
): Promise<{ proposed_action: string; confidence: number; reasoning: string; reliability_impact: number }> {
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
- no_show: if reached_arrived is false, propose full_refund.
- late_arrival: if late_by_minutes > 30, propose service_credit_150; if > 60, propose partial_refund_150.
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

  const geminiResult = await reasonWithGemini(type, evidence, customerComment);

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
    status:            geminiResult.confidence >= 0.65 ? "proposed" : "escalated",
    reliability_impact: geminiResult.reliability_impact,
    created_at:        new Date().toISOString(),
  };

  const disputes = readDisputes();
  disputes.push(dispute);
  writeDisputes(disputes);

  return dispute;
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
    // Apply reliability impact to provider
    if (dispute.reliability_impact < 0) {
      applyDisputeOutcome(dispute.provider_id, "lost", dispute.booking_id);
    } else {
      applyDisputeOutcome(dispute.provider_id, "won", dispute.booking_id);
    }
  } else {
    // Either party rejected → escalate to human review
    dispute.status = "escalated";
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
