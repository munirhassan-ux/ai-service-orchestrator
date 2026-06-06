// Negotiation Engine — orchestrates the A2A auction.
// Pipeline: CFP broadcast → collect bids → Customer Agent scores → accept/counter → lock deal.
// Max 1 CFP round + 1 counter round, max 5 provider agents. ~2–4 Gemini calls total.

import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { haversine as _haversine } from "../utils/haversine.js";
import { evaluateCFP, respondToCounter, Bid, CFP } from "./providerAgent.js";
import { runAuction, AuctionInput } from "./customerAgent.js";
import { RankedProvider } from "./providerMatcher.js";
import { ParsedIntent } from "./intentParser.js";

// ── Terminal colour helpers (local) ──────────────────────────────────────────
const C = {
  reset: "\x1b[0m", bold: "\x1b[1m", dim: "\x1b[2m",
  cyan: "\x1b[36m", green: "\x1b[32m", yellow: "\x1b[33m",
  red: "\x1b[31m", magenta: "\x1b[35m", blue: "\x1b[34m",
};
const W = 62;
const hline = (ch = "─") => ch.repeat(W);
function _sleep(ms: number) { return new Promise(r => setTimeout(r, ms)); }
function _tag(role: "CA" | "PA", name: string) {
  const col = role === "CA" ? C.cyan : C.magenta;
  return `${col}${C.bold}[${role === "CA" ? "CustomerAgent" : `ProviderAgent:${name}`}]${C.reset}`;
}
function _banner(title: string) {
  console.log(`\n${C.cyan}${C.bold}╔${"═".repeat(W - 2)}╗${C.reset}`);
  const pad = Math.floor((W - 2 - title.length) / 2);
  console.log(`${C.cyan}${C.bold}║${" ".repeat(pad)}${title}${" ".repeat(W - 2 - pad - title.length)}║${C.reset}`);
  console.log(`${C.cyan}${C.bold}╚${"═".repeat(W - 2)}╝${C.reset}\n`);
}

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const contractsFile = path.join(__dirname, "../../data/mock_contracts.json");

function _utility(price: number, reliability: number, etaMin: number, budgetCeiling: number): number {
  const priceScore = budgetCeiling > 0 ? Math.max(0, 1 - price / budgetCeiling) : 0.5;
  const relScore   = reliability / 100;
  const etaScore   = Math.max(0, 1 - etaMin / 90);
  return 0.40 * relScore + 0.35 * priceScore + 0.25 * etaScore;
}

function _rejectionReason(bid: Bid, winner: Bid): string {
  const relDiff   = winner.reliability_snapshot - bid.reliability_snapshot;
  const priceDiff = bid.price - winner.price;
  const etaDiff   = bid.eta_min - winner.eta_min;
  if (relDiff > 8)    return `Lower reliability (${Math.round(bid.reliability_snapshot)} vs ${Math.round(winner.reliability_snapshot)})`;
  if (priceDiff > 100) return `Higher price (Rs. ${bid.price} vs Rs. ${winner.price})`;
  if (etaDiff > 10)   return `Slower arrival (${bid.eta_min} min vs ${winner.eta_min} min)`;
  return "Lower composite score";
}

function _buildEvaluations(top5: RankedProvider[], round1Bids: Bid[], winner: Bid | undefined, budgetCeiling: number): BidEvaluation[] {
  return top5.map(p => {
    const bid = round1Bids.find(b => b.provider_id === p.provider_id);
    if (!bid || !bid.accepted) {
      return {
        provider: p.provider_id,
        provider_name: p.name,
        status: "declined" as const,
        rejection_reason: bid?.reject_reason ?? "Provider unavailable",
      };
    }
    const isWinner = winner && bid.provider_id === winner.provider_id;
    const utility  = Math.round(_utility(bid.price, bid.reliability_snapshot, bid.eta_min, budgetCeiling) * 100) / 100;
    return {
      provider:       bid.provider_id,
      provider_name:  p.name,
      price:          bid.price,
      eta_min:        bid.eta_min,
      reliability:    Math.round(bid.reliability_snapshot),
      utility_score:  utility,
      status:         isWinner ? "selected" as const : "not_selected" as const,
      rejection_reason: isWinner ? null : (winner ? _rejectionReason(bid, winner) : "Not selected"),
    };
  });
}

export interface Contract {
  contract_id: string;
  booking_id: string | null;
  provider_id: string;
  customer_id: string;
  agreed_price: number;
  agreed_slot: string;
  negotiation_rounds: number;
  cfp_log: Bid[];
  signed_by: { customer_agent: boolean; provider_agent: boolean };
  event_log: Array<{ event: string; ts: string }>;
  created_at: string;
}

export interface BidEvaluation {
  provider: string;
  provider_name: string;
  price?: number;
  eta_min?: number;
  reliability?: number;
  utility_score?: number;
  status: "selected" | "not_selected" | "declined";
  rejection_reason: string | null;
}

export interface AuctionTrace {
  phase: "negotiation";
  cfp_sent_to: string[];
  proposals: Array<{ provider: string; provider_name: string; price: number; eta_min: number; confidence: number }>;
  counter_round?: Array<{ provider: string; provider_name: string; counter_price: number; response_price: number; accepted: boolean }>;
  bid_evaluations?: BidEvaluation[];
  customer_agent_reasoning: string;
  rounds: number;
  outcome: "deal_locked" | "no_deal";
  contract_id?: string;
}

function readContracts(): Contract[] {
  try {
    if (!fs.existsSync(contractsFile)) return [];
    return JSON.parse(fs.readFileSync(contractsFile, "utf-8"));
  } catch { return []; }
}

function writeContracts(data: Contract[]): void {
  fs.writeFileSync(contractsFile, JSON.stringify(data, null, 2));
}

function generateContractId(): string {
  const date = new Date().toISOString().slice(0, 10).replace(/-/g, "");
  const seq  = String(readContracts().length + 1).padStart(4, "0");
  return `DEAL-${date}-${seq}`;
}

export async function runNegotiation(
  candidates: RankedProvider[],   // top 5 from ProviderMatcher
  intent: ParsedIntent,
  customerId: string,
  customerLat: number,
  customerLng: number
): Promise<{ contract: Contract | null; trace: AuctionTrace }> {
  const top5 = candidates.slice(0, 5);

  const cfp: CFP = {
    job_spec:       `${intent.service_type} in ${intent.location}`,
    service_type:   intent.service_type,
    area:           intent.location,
    complexity:     (intent as any).complexity ?? "basic",
    budget_ceiling: (intent as any).budget_ceiling ?? 0,
    urgency:        intent.urgency ?? "medium",
    preferred_time: intent.preferred_time ?? "flexible",
  };

  // ── LIVE TERMINAL: Session header ────────────────────────────────────
  _banner("  HAAZIR — A2A NEGOTIATION SESSION  ");
  console.log(`${_tag("CA", "")} Broadcast CFP → ${top5.length} provider agent(s)`);
  console.log(`${C.dim}  Job: ${cfp.job_spec} | Urgency: ${(cfp.urgency).toUpperCase()} | Time: ${cfp.preferred_time}${C.reset}`);
  console.log(`\n${C.cyan}${hline()}${C.reset}`);
  await _sleep(200);

  // ── Round 1: Broadcast CFP and collect bids ──────────────────────────
  console.log(`\n${C.bold}  ROUND 1 — CFP RESPONSE COLLECTION${C.reset}`);
  const round1Bids: Bid[] = [];
  for (const p of top5) {
    const dist = _haversine(customerLat, customerLng, p.location.latitude, p.location.longitude);
    console.log(`\n${_tag("PA", p.name)} Evaluating CFP... (distance: ${dist.toFixed(1)}km, rating: ${p.rating}★)`);
    await _sleep(180);
    const bid = evaluateCFP(p, cfp, dist);
    if (bid.accepted) {
      console.log(`${_tag("PA", p.name)} ${C.green}✅ BID SUBMITTED${C.reset} — Rs.${bid.price} | ETA: ${bid.eta_min}min | Confidence: ${Math.round(bid.confidence * 100)}%`);
    } else {
      console.log(`${_tag("PA", p.name)} ${C.red}❌ DECLINED${C.reset} — ${bid.reject_reason}`);
    }
    await _sleep(150);
    round1Bids.push(bid);
  }

  const accepted1 = round1Bids.filter(b => b.accepted);
  console.log(`\n${C.cyan}${hline()}${C.reset}`);
  console.log(`${_tag("CA", "")} ${accepted1.length} bid(s) received. Scoring with utility function...`);
  await _sleep(300);

  const auctionInput: AuctionInput = {
    bids:             round1Bids,
    budget_ceiling:   cfp.budget_ceiling,
    urgency:          cfp.urgency,
    session_language: (intent.language as any) ?? "roman_urdu",
  };

  const decision = await runAuction(auctionInput);
  let rounds = 1;

  // Log CustomerAgent decision reasoning
  if (decision.accepted_bid) {
    console.log(`${_tag("CA", "")} ${C.yellow}Top bid:${C.reset} ${decision.accepted_bid.provider_id} — Rs.${decision.accepted_bid.price}`);
  }
  console.log(`${_tag("CA", "")} ${C.dim}Reasoning: ${decision.reasoning.slice(0, 80)}...${C.reset}`);
  await _sleep(200);

  const traceBase: Omit<AuctionTrace, "outcome" | "contract_id"> = {
    phase:     "negotiation",
    cfp_sent_to: top5.map(p => p.provider_id),
    proposals:   round1Bids.filter(b => b.accepted).map(b => ({
      provider:       b.provider_id,
      provider_name:  top5.find(p => p.provider_id === b.provider_id)?.name ?? b.provider_id,
      price:          b.price,
      eta_min:        b.eta_min,
      confidence:     b.confidence,
    })),
    bid_evaluations: _buildEvaluations(top5, round1Bids, decision.accepted_bid, cfp.budget_ceiling),
    customer_agent_reasoning: decision.reasoning,
    rounds,
  };

  // ── Deal accepted in Round 1 ─────────────────────────────────────────
  if (decision.action === "accept" && decision.accepted_bid) {
    console.log(`\n${_tag("CA", "")} ${C.green}${C.bold}✅ ACCEPT — Rs.${decision.accepted_bid.price} from ${decision.accepted_bid.provider_id}${C.reset}`);
    const contract = _lockDeal(decision.accepted_bid, round1Bids, customerId, rounds);
    console.log(`${C.green}${C.bold}🔒 DEAL LOCKED — Contract: ${contract.contract_id}${C.reset}`);
    console.log(`${C.cyan}${hline()}${C.reset}\n`);
    return {
      contract,
      trace: { ...traceBase, rounds, outcome: "deal_locked", contract_id: contract.contract_id },
    };
  }

  // ── Round 2: Counter-offer ───────────────────────────────────────────
  if (decision.action === "counter" && decision.counter_targets) {
    rounds = 2;
    console.log(`\n${C.cyan}${hline()}${C.reset}`);
    console.log(`\n${C.bold}  ROUND 2 — COUNTER-OFFER${C.reset}`);
    console.log(`${_tag("CA", "")} ${C.yellow}Budget ceiling exceeded — sending counter-offers...${C.reset}`);
    await _sleep(250);

    const counterRound: AuctionTrace["counter_round"] = [];
    const round2Bids: Bid[] = [];

    for (const target of decision.counter_targets) {
      const originalBid = round1Bids.find(b => b.provider_id === target.provider_id);
      if (!originalBid) continue;
      const providerData = top5.find(p => p.provider_id === target.provider_id);
      if (!providerData) continue;

      console.log(`\n${_tag("CA", "")} → ${C.yellow}Counter to ${target.provider_id}:${C.reset} Rs.${target.counter_price}`);
      await _sleep(200);
      console.log(`${_tag("PA", providerData.name)} Evaluating counter...`);
      await _sleep(250);

      const response = respondToCounter(providerData, originalBid, target.counter_price);
      counterRound.push({
        provider:       target.provider_id,
        provider_name:  providerData.name,
        counter_price:  target.counter_price,
        response_price: response.price,
        accepted:       response.accepted,
      });

      if (response.accepted) {
        console.log(`${_tag("PA", providerData.name)} ${C.green}✅ ACCEPTED Rs.${response.price}${C.reset} (strategy: meet-in-middle)`);
        round2Bids.push(response);
      } else {
        console.log(`${_tag("PA", providerData.name)} ${C.red}❌ REJECTED${C.reset} — ${response.reject_reason ?? "floor price not met"}`);
      }
      await _sleep(150);
    }

    if (round2Bids.length > 0) {
      round2Bids.sort((a, b) => a.price - b.price);
      const best = round2Bids[0];
      console.log(`\n${_tag("CA", "")} ${C.green}${C.bold}✅ ACCEPT — Rs.${best.price} from ${best.provider_id}${C.reset}`);
      const contract = _lockDeal(best, [...round1Bids, ...round2Bids], customerId, rounds);
      console.log(`${C.green}${C.bold}🔒 DEAL LOCKED — Contract: ${contract.contract_id}${C.reset}`);
      console.log(`${C.cyan}${hline()}${C.reset}\n`);
      return {
        contract,
        trace: {
          ...traceBase,
          counter_round: counterRound,
          customer_agent_reasoning: decision.reasoning,
          rounds,
          outcome: "deal_locked",
          contract_id: contract.contract_id,
        },
      };
    }
  }

  // ── No deal after all rounds ─────────────────────────────────────────
  console.log(`\n${C.red}${C.bold}❌ NO DEAL — All negotiation rounds exhausted.${C.reset}`);
  console.log(`${C.cyan}${hline()}${C.reset}\n`);
  return {
    contract: null,
    trace: { ...traceBase, rounds, outcome: "no_deal" },
  };
}

function _lockDeal(
  winningBid: Bid,
  allBids: Bid[],
  customerId: string,
  rounds: number
): Contract {
  const contract: Contract = {
    contract_id:       generateContractId(),
    booking_id:        null,  // linked by BookingSimulator after createBooking
    provider_id:       winningBid.provider_id,
    customer_id:       customerId,
    agreed_price:      winningBid.price,
    agreed_slot:       winningBid.slot,
    negotiation_rounds: rounds,
    cfp_log:           allBids,
    signed_by:         { customer_agent: true, provider_agent: true },
    event_log:         [{ event: "deal_locked", ts: new Date().toISOString() }],
    created_at:        new Date().toISOString(),
  };

  const contracts = readContracts();
  contracts.push(contract);
  writeContracts(contracts);
  return contract;
}

export function linkBookingToContract(contractId: string, bookingId: string): void {
  const contracts = readContracts();
  const idx = contracts.findIndex(c => c.contract_id === contractId);
  if (idx !== -1) {
    contracts[idx].booking_id = bookingId;
    writeContracts(contracts);
  }
}

export function getContract(contractId: string): Contract | undefined {
  return readContracts().find(c => c.contract_id === contractId);
}

export function appendEventToContract(contractId: string, event: string): void {
  const contracts = readContracts();
  const idx = contracts.findIndex(c => c.contract_id === contractId);
  if (idx !== -1) {
    contracts[idx].event_log.push({ event, ts: new Date().toISOString() });
    writeContracts(contracts);
  }
}
