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

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const contractsFile = path.join(__dirname, "../../data/mock_contracts.json");

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

export interface AuctionTrace {
  phase: "negotiation";
  cfp_sent_to: string[];
  proposals: Array<{ provider: string; price: number; eta_min: number; confidence: number }>;
  counter_round?: Array<{ provider: string; counter_price: number; response_price: number; accepted: boolean }>;
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
    area:           intent.location,          // area only — exact address withheld until CONFIRM
    complexity:     (intent as any).complexity ?? "basic",
    budget_ceiling: (intent as any).budget_ceiling ?? 0,
    urgency:        intent.urgency ?? "medium",
    preferred_time: intent.preferred_time ?? "flexible",
  };

  // ── Round 1: Broadcast CFP and collect bids ──────────────────────────
  const round1Bids: Bid[] = top5.map(p => {
    const dist = _haversine(customerLat, customerLng, p.location.latitude, p.location.longitude);
    return evaluateCFP(p, cfp, dist);
  });

  const auctionInput: AuctionInput = {
    bids:             round1Bids,
    budget_ceiling:   cfp.budget_ceiling,
    urgency:          cfp.urgency,
    session_language: (intent.language as any) ?? "roman_urdu",
  };

  const decision = await runAuction(auctionInput);
  let rounds = 1;

  const traceBase: Omit<AuctionTrace, "outcome" | "contract_id"> = {
    phase:     "negotiation",
    cfp_sent_to: top5.map(p => p.provider_id),
    proposals:   round1Bids.filter(b => b.accepted).map(b => ({
      provider:    b.provider_id,
      price:       b.price,
      eta_min:     b.eta_min,
      confidence:  b.confidence,
    })),
    customer_agent_reasoning: decision.reasoning,
    rounds,
  };

  // ── Deal accepted in Round 1 ─────────────────────────────────────────
  if (decision.action === "accept" && decision.accepted_bid) {
    const contract = _lockDeal(decision.accepted_bid, round1Bids, customerId, rounds);
    return {
      contract,
      trace: { ...traceBase, rounds, outcome: "deal_locked", contract_id: contract.contract_id },
    };
  }

  // ── Round 2: Counter-offer ───────────────────────────────────────────
  if (decision.action === "counter" && decision.counter_targets) {
    rounds = 2;
    const counterRound: AuctionTrace["counter_round"] = [];
    const round2Bids: Bid[] = [];

    for (const target of decision.counter_targets) {
      const originalBid = round1Bids.find(b => b.provider_id === target.provider_id);
      if (!originalBid) continue;
      const providerData = top5.find(p => p.provider_id === target.provider_id);
      if (!providerData) continue;

      const response = respondToCounter(providerData, originalBid, target.counter_price);
      counterRound.push({
        provider:       target.provider_id,
        counter_price:  target.counter_price,
        response_price: response.price,
        accepted:       response.accepted,
      });
      if (response.accepted) round2Bids.push(response);
    }

    if (round2Bids.length > 0) {
      // Accept cheapest accepted counter response
      round2Bids.sort((a, b) => a.price - b.price);
      const best = round2Bids[0];
      const contract = _lockDeal(best, [...round1Bids, ...round2Bids], customerId, rounds);
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
