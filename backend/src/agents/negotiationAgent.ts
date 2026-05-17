import { GoogleGenerativeAI } from "@google/generative-ai";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const negotiationsFile = path.join(__dirname, "../../data/mock_negotiations.json");

import { softLockSlot, releaseSoftLock, convertSoftLockToHardLock } from "./bookingSimulator.js";

export type NegotiationStatus =
  | "pending_provider"
  | "pending_customer"
  | "agreed"
  | "declined"
  | "abandoned"
  | "ai_suggested";

export interface NegotiationMessage {
  from: "customer" | "provider" | "ai";
  message: string;
  offered_price: number;
  timestamp: string;
}

export interface NegotiationThread {
  id: string;
  booking_request_id: string;
  provider_id: string;
  customer_id: string;
  session_id?: string;
  ai_quote: number;
  final_price: number | null;
  status: NegotiationStatus;
  round: number;
  max_rounds: number;
  messages: NegotiationMessage[];
  created_at: string;
  updated_at: string;
}

function readThreads(): { threads: NegotiationThread[] } {
  try {
    return JSON.parse(fs.readFileSync(negotiationsFile, "utf-8"));
  } catch {
    return { threads: [] };
  }
}

function writeThreads(data: { threads: NegotiationThread[] }) {
  fs.writeFileSync(negotiationsFile, JSON.stringify(data, null, 2));
}

function generateId(): string {
  return `NEG-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
}

import { logTraceEvent } from "../trace.js";

// Create a new negotiation thread when AI sends quote to provider
export function createNegotiationThread(
  bookingRequestId: string,
  providerId: string,
  customerId: string,
  aiQuote: number,
  sessionId?: string,
  preferredTime?: string
): NegotiationThread {
  const data = readThreads();

  let slotTime: string | undefined;
  if (sessionId && preferredTime) {
    slotTime = softLockSlot(providerId, preferredTime, sessionId);
    logTraceEvent(sessionId, {
      agent: "NegotiationAgent",
      gemini_decision: `Soft-locking provider ${providerId} slot for preferred time ${preferredTime}`,
      slot_soft_locked: { provider_id: providerId, slot_time: slotTime }
    });
  }

  const thread: NegotiationThread = {
    id: generateId(),
    booking_request_id: bookingRequestId,
    provider_id: providerId,
    customer_id: customerId,
    session_id: sessionId,
    ai_quote: aiQuote,
    final_price: null,
    status: "pending_provider",
    round: 0,
    max_rounds: 3,
    messages: [
      {
        from: "ai",
        message: `AI has quoted Rs. ${aiQuote} for this job. Do you accept, decline, or counter-offer?`,
        offered_price: aiQuote,
        timestamp: new Date().toISOString(),
      },
    ],
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  data.threads.push(thread);
  writeThreads(data);

  console.log(`[NegotiationAgent] Thread created: ${thread.id} | Quote: Rs. ${aiQuote} | Session: ${sessionId}`);
  return thread;
}

// Provider responds: accept, decline, or counter
export async function providerRespond(
  threadId: string,
  action: "accept" | "decline" | "counter",
  counterPrice?: number,
  reason?: string
): Promise<NegotiationThread> {
  const data = readThreads();
  const thread = data.threads.find((t) => t.id === threadId);
  if (!thread) throw new Error(`Thread ${threadId} not found`);

  thread.round += 1;
  thread.updated_at = new Date().toISOString();

  if (action === "accept") {
    thread.status = "agreed";
    thread.final_price = thread.messages[thread.messages.length - 1].offered_price;
    thread.messages.push({
      from: "provider",
      message: `Provider accepted Rs. ${thread.final_price}. Booking confirmed!`,
      offered_price: thread.final_price,
      timestamp: new Date().toISOString(),
    });
    if (thread.session_id) {
      convertSoftLockToHardLock(thread.session_id);
    }
  } else if (action === "decline") {
    thread.status = "declined";
    thread.messages.push({
      from: "provider",
      message: reason || "Provider declined this job.",
      offered_price: 0,
      timestamp: new Date().toISOString(),
    });
    if (thread.session_id) {
      releaseSoftLock(thread.session_id);
    }
  } else if (action === "counter" && counterPrice) {
    // Validate counter is reasonable (within 50% of AI quote)
    const minAcceptable = thread.ai_quote * 0.5;
    const maxAcceptable = thread.ai_quote * 2.0;
    if (counterPrice < minAcceptable || counterPrice > maxAcceptable) {
      throw new Error(`Counter price Rs. ${counterPrice} is outside acceptable range.`);
    }

    thread.status = "pending_customer";
    thread.messages.push({
      from: "provider",
      message: `My rate for this job is Rs. ${counterPrice}. Can you meet that?`,
      offered_price: counterPrice,
      timestamp: new Date().toISOString(),
    });

    // Check if max rounds reached — suggest midpoint
    if (thread.round >= thread.max_rounds) {
      const customerLastOffer =
        thread.messages.filter((m) => m.from === "customer").slice(-1)[0]?.offered_price ||
        thread.ai_quote;
      const midpoint = Math.round(((counterPrice + customerLastOffer) / 2) / 10) * 10;

      const aiMsg = await generateAIMidpointMessage(thread, midpoint);
      thread.status = "ai_suggested";
      thread.messages.push({
        from: "ai",
        message: aiMsg,
        offered_price: midpoint,
        timestamp: new Date().toISOString(),
      });
    }
  }

  writeThreads(data);
  console.log(`[NegotiationAgent] Provider responded: ${action} | Thread: ${threadId}`);
  return thread;
}

// Customer responds: accept, decline, or counter
export async function customerRespond(
  threadId: string,
  action: "accept" | "decline" | "counter",
  counterPrice?: number
): Promise<NegotiationThread> {
  const data = readThreads();
  const thread = data.threads.find((t) => t.id === threadId);
  if (!thread) throw new Error(`Thread ${threadId} not found`);

  thread.round += 1;
  thread.updated_at = new Date().toISOString();

  const lastOfferedPrice = thread.messages[thread.messages.length - 1].offered_price;

  if (action === "accept") {
    thread.status = "agreed";
    thread.final_price = lastOfferedPrice;
    thread.messages.push({
      from: "customer",
      message: `Deal! Accepted at Rs. ${thread.final_price}.`,
      offered_price: thread.final_price,
      timestamp: new Date().toISOString(),
    });
    if (thread.session_id) {
      convertSoftLockToHardLock(thread.session_id);
    }
  } else if (action === "decline") {
    thread.status = "abandoned";
    thread.messages.push({
      from: "customer",
      message: "Customer declined. Looking for another provider.",
      offered_price: 0,
      timestamp: new Date().toISOString(),
    });
    if (thread.session_id) {
      releaseSoftLock(thread.session_id);
    }
  } else if (action === "counter" && counterPrice) {
    thread.status = "pending_provider";
    thread.messages.push({
      from: "customer",
      message: `Rs. ${counterPrice} — that's my final offer.`,
      offered_price: counterPrice,
      timestamp: new Date().toISOString(),
    });

    // Check if max rounds reached
    if (thread.round >= thread.max_rounds) {
      const providerLastOffer =
        thread.messages.filter((m) => m.from === "provider").slice(-1)[0]?.offered_price ||
        thread.ai_quote;
      const midpoint = Math.round(((counterPrice + providerLastOffer) / 2) / 10) * 10;

      const aiMsg = await generateAIMidpointMessage(thread, midpoint);
      thread.status = "ai_suggested";
      thread.messages.push({
        from: "ai",
        message: aiMsg,
        offered_price: midpoint,
        timestamp: new Date().toISOString(),
      });
    }
  }

  writeThreads(data);
  console.log(`[NegotiationAgent] Customer responded: ${action} | Thread: ${threadId}`);
  return thread;
}

// Both parties accept AI midpoint suggestion
export function acceptMidpoint(threadId: string, acceptedBy: "customer" | "provider"): NegotiationThread {
  const data = readThreads();
  const thread = data.threads.find((t) => t.id === threadId);
  if (!thread) throw new Error(`Thread ${threadId} not found`);

  const midpointMsg = thread.messages.filter((m) => m.from === "ai").slice(-1)[0];
  if (!midpointMsg) throw new Error("No AI midpoint found");

  // Mark the party's acceptance — only finalize when both accept
  const acceptMsg = `${acceptedBy === "customer" ? "Customer" : "Provider"} accepted AI midpoint: Rs. ${midpointMsg.offered_price}`;
  thread.messages.push({
    from: acceptedBy,
    message: acceptMsg,
    offered_price: midpointMsg.offered_price,
    timestamp: new Date().toISOString(),
  });

  // Check if both have now accepted midpoint
  const bothAccepted =
    thread.messages.filter(
      (m) =>
        (m.from === "customer" || m.from === "provider") &&
        m.offered_price === midpointMsg.offered_price
    ).length >= 2;

  if (bothAccepted) {
    thread.status = "agreed";
    thread.final_price = midpointMsg.offered_price;
    if (thread.session_id) {
      convertSoftLockToHardLock(thread.session_id);
    }
  }

  thread.updated_at = new Date().toISOString();
  writeThreads(data);

  console.log(`[NegotiationAgent] Midpoint ${bothAccepted ? "AGREED" : "awaiting other party"}: Rs. ${midpointMsg.offered_price}`);
  return thread;
}

// Either party declines the AI midpoint
export function declineMidpoint(threadId: string, declinedBy: "customer" | "provider"): NegotiationThread {
  const data = readThreads();
  const thread = data.threads.find((t) => t.id === threadId);
  if (!thread) throw new Error(`Thread ${threadId} not found`);

  thread.status = "abandoned";
  thread.messages.push({
    from: declinedBy,
    message: `${declinedBy === "customer" ? "Customer" : "Provider"} declined the fair midpoint suggestion. Thread abandoned.`,
    offered_price: 0,
    timestamp: new Date().toISOString(),
  });
  if (thread.session_id) {
    releaseSoftLock(thread.session_id);
  }

  thread.updated_at = new Date().toISOString();
  writeThreads(data);

  console.log(`[NegotiationAgent] Midpoint DECLINED by ${declinedBy}. Rerouting logic triggered.`);
  return thread;
}

export function getThread(threadId: string): NegotiationThread | undefined {
  return readThreads().threads.find((t) => t.id === threadId);
}

async function generateAIMidpointMessage(
  thread: NegotiationThread,
  midpoint: number
): Promise<string> {
  const genAI = new GoogleGenerativeAI(process.env.GOOGLE_API_KEY!);
  const model = genAI.getGenerativeModel({ 
    model: "gemini-3.1-flash-lite",
    generationConfig: { maxOutputTokens: 150 }
  });
  
  const prompt = `You are an AI mediator for a Pakistani home services app. 
Negotiation has stalled after ${thread.round} rounds.
Customer offer: Rs. ${thread.messages.filter(m => m.from === "customer").slice(-1)[0]?.offered_price || thread.ai_quote}
Provider offer: Rs. ${thread.messages.filter(m => m.from === "provider").slice(-1)[0]?.offered_price || thread.ai_quote}
Midpoint: Rs. ${midpoint}

Write a short, friendly suggestion (1-2 sentences, mix English/Roman Urdu is fine) proposing the midpoint. Be concise.`;

  const result = await model.generateContent(prompt);
  const response = await result.response;
  
  return response.text().trim() || `Both offers are close. Suggested fair price: Rs. ${midpoint}. Dono parties ke liye fair hai.`;
}
