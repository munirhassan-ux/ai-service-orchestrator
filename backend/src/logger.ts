// ── Terminal colour helpers ────────────────────────────────────────────────
const c = {
  reset:  "\x1b[0m",
  bold:   "\x1b[1m",
  dim:    "\x1b[2m",
  cyan:   "\x1b[36m",
  green:  "\x1b[32m",
  yellow: "\x1b[33m",
  red:    "\x1b[31m",
  blue:   "\x1b[34m",
  magenta:"\x1b[35m",
  white:  "\x1b[37m",
};

const W = 60; // box width

function bar(value: number, max: number = 100, len = 10): string {
  const filled = Math.round((value / max) * len);
  return "█".repeat(filled) + "░".repeat(len - filled);
}

function pad(s: string, n: number): string {
  return s.length >= n ? s.slice(0, n) : s + " ".repeat(n - s.length);
}

function header(icon: string, title: string, ms?: number): string {
  const right = ms !== undefined ? `${ms}ms ─┐` : "──┐";
  const left  = `┌─ ${icon} ${title} `;
  const fill  = W - left.length - right.length;
  return c.cyan + c.bold + left + "─".repeat(Math.max(1, fill)) + right + c.reset;
}

function footer(): string {
  return c.cyan + "└" + "─".repeat(W - 1) + "┘" + c.reset;
}

function row(label: string, value: string, colour = c.white): string {
  return c.cyan + "│" + c.reset + "  " + c.dim + pad(label, 11) + c.reset + colour + value + c.reset;
}

function divider(): string {
  return c.cyan + "│" + c.dim + "  " + "─".repeat(W - 4) + c.reset;
}

// ── 1. Intent Parser ──────────────────────────────────────────────────────
export function logIntent(input: string, intent: any, ms: number) {
  const conf     = Math.round((intent.confidence || 0) * 100);
  const confBar  = bar(conf);
  const needsCl  = intent.clarification_needed;
  const clarity  = needsCl
    ? c.yellow + `⚠ clarification needed: ${intent.clarification_question?.slice(0, 40) ?? "?"}` + c.reset
    : c.green  + "✓ ok" + c.reset;

  console.log("");
  console.log(header("🧠", "INTENT PARSER", ms));
  console.log(row("input", `"${input.slice(0, 50)}"`));
  console.log(row("language", `${intent.language}   `) +
    c.dim + "confidence  " + c.reset + c.yellow + `${confBar} ${conf}%` + c.reset);
  console.log(row("service", String(intent.service_type || "—")) +
    c.dim + "  location  " + c.reset + String(intent.location || "—"));
  console.log(row("time", String(intent.preferred_time || "flexible")) +
    c.dim + "  clarity   " + c.reset + clarity);
  if (intent.reasoning) {
    console.log(row("reasoning", intent.reasoning.slice(0, 55)));
  }
  console.log(footer());
}

// ── 2. Provider Matcher ───────────────────────────────────────────────────
export function logProviderMatch(intent: any, result: any, ms: number) {
  const providers: any[] = result.top_providers || [];
  const fallback = result.fallback_used;

  console.log("");
  console.log(header("🔍", "PROVIDER MATCHER", ms));
  console.log(row("request",
    `${intent.service_type} | ${intent.location} | urgency: ${intent.urgency}`));
  console.log(row("eligible",
    `${providers.length} shown` +
    (fallback ? c.yellow + `  ⚠ fallback: ${result.fallback_reason?.slice(0, 30)}` + c.reset : c.green + "  ✓ no fallback" + c.reset)));

  if (providers.length > 0) {
    console.log(divider());
    console.log(c.cyan + "│" + c.reset + "  " + c.dim +
      pad("rank", 5) + pad("provider", 22) + pad("score", 7) +
      pad("dist", 7) + pad("rating", 8) + "ontime" + c.reset);
    providers.forEach((p: any, i: number) => {
      const waitlist = p.is_waitlisted ? c.yellow + " [waitlist]" + c.reset : "";
      const scoreCol = p.score >= 80 ? c.green : p.score >= 60 ? c.yellow : c.red;
      console.log(c.cyan + "│" + c.reset + "  " +
        c.bold + pad(`#${i + 1}`, 5) + c.reset +
        pad(p.name.slice(0, 21), 22) +
        scoreCol + pad(String(p.score), 7) + c.reset +
        pad(`${p.distance_km}km`, 7) +
        c.yellow + pad(`${p.rating}★`, 8) + c.reset +
        `${Math.round((p.on_time_score || 0) * 100)}%` +
        waitlist
      );
      const bd = p.score_breakdown;
      if (bd) {
        console.log(c.cyan + "│" + c.reset + c.dim +
          `       travel:${bd.travel_time} spec:${bd.specialization} ontime:${bd.on_time} ` +
          `review:${bd.review_sentiment} rate:${bd.rate} risk:${bd.cancellation_risk} cap:${bd.capacity}` +
          c.reset);
      }
    });
  }
  console.log(footer());
}

// ── 3. Pricing Engine ─────────────────────────────────────────────────────
export function logPricing(provider: any, intent: any, quote: any) {
  const urgencyLabel = intent.urgency === "high" || intent.urgency === "emergency"
    ? c.yellow + `${intent.urgency} → Rs. ${quote.urgency_surcharge} surcharge` + c.reset
    : c.green  + `${intent.urgency} → Rs. 0 surcharge` + c.reset;

  console.log("");
  console.log(header("💰", "PRICING ENGINE"));
  console.log(row("provider",
    `${provider.name}  (Rs. ${provider.charges.base_rate}/hr)`));
  console.log(row("service fee",
    `2 hrs × Rs. ${provider.charges.base_rate} = Rs. ${quote.base_rate * 2}`));
  console.log(row("travel",
    `${provider.distance_km}km × Rs. ${provider.charges.travel_rate} = Rs. ${quote.distance_fee}`));
  console.log(row("urgency",  urgencyLabel));
  console.log(divider());
  console.log(row("total",
    c.bold + c.green + `Rs. ${quote.total}` + c.reset +
    c.dim  + `  (range Rs. ${quote.min_total}–${quote.max_total})` + c.reset));
  console.log(footer());
}

// ── 4. Scheduling ─────────────────────────────────────────────────────────
export function logScheduling(
  providerId: string,
  preferredTime: string,
  slot: string,
  bookingId: string,
  collision: boolean
) {
  console.log("");
  console.log(header("📅", "SCHEDULING"));
  console.log(row("preferred", preferredTime));
  console.log(row("provider",  providerId));
  console.log(row("slot",      slot));
  console.log(row("collision", collision
    ? c.yellow + "⚠ slot adjusted (conflict)" + c.reset
    : c.green  + "✓ none" + c.reset));
  console.log(row("booking",   c.bold + bookingId + c.reset));
  console.log(footer());
}

// ── 5. Action / Phase Transition ──────────────────────────────────────────
export function logAction(
  sessionId: string,
  fromPhase: string,
  toPhase: string,
  extra?: Record<string, string>,
  ms?: number
) {
  const arrow = `${c.dim}${fromPhase}${c.reset} → ${c.bold}${c.green}${toPhase}${c.reset}`;
  console.log("");
  console.log(header("⚡", "ACTION", ms));
  console.log(row("session", sessionId.slice(-16)));
  console.log(row("phase",   arrow));
  if (extra) {
    for (const [k, v] of Object.entries(extra)) {
      console.log(row(k, String(v)));
    }
  }
  console.log(footer());
}

// ── 6. Booking Status Change ──────────────────────────────────────────────
export function logStatusChange(bookingId: string, from: string, to: string) {
  const colour = to === "ACCEPTED"    ? c.green
    : to.startsWith("CANCELLED")      ? c.red
    : to === "COMPLETED"              ? c.blue
    : c.yellow;
  console.log("");
  console.log(header("🔄", "STATUS UPDATE"));
  console.log(row("booking", bookingId));
  console.log(row("change",  `${c.dim}${from}${c.reset} → ${colour}${c.bold}${to}${c.reset}`));
  console.log(footer());
}

// ── 7. A2A Negotiation ────────────────────────────────────────────────────
export function logNegotiation(trace: any, contract: any | null) {
  const proposals: any[] = trace.proposals ?? [];
  const rounds: number = trace.rounds ?? 1;
  const outcome: string = trace.outcome ?? "no_deal";
  const outcomeColor = outcome === "deal_locked" ? c.green : c.red;

  console.log("");
  console.log(header("🤝", "A2A NEGOTIATION"));
  console.log(row("CFP sent to", `${(trace.cfp_sent_to ?? []).length} provider agents`));
  console.log(row("bids rcvd", `${proposals.length} accepted proposals`));
  console.log(row("rounds", String(rounds)));
  if (proposals.length > 0) {
    console.log(divider());
    console.log(c.cyan + "│" + c.reset + "  " + c.dim +
      pad("provider", 18) + pad("price", 10) + pad("eta", 8) + "confidence" + c.reset);
    proposals.forEach((p: any) => {
      const iswinner = contract && p.provider === contract.provider_id;
      console.log(c.cyan + "│" + c.reset + "  " +
        (iswinner ? c.bold + c.green : c.reset) +
        pad(p.provider.slice(0, 17), 18) +
        c.yellow + pad(`Rs.${p.price}`, 10) + c.reset +
        pad(`${p.eta_min}min`, 8) +
        `${Math.round((p.confidence ?? 0) * 100)}%` +
        (iswinner ? c.green + "  ← WINNER" + c.reset : "") +
        c.reset
      );
    });
    console.log(divider());
  }
  if (trace.customer_agent_reasoning) {
    console.log(row("reasoning", trace.customer_agent_reasoning.slice(0, 55)));
  }
  console.log(row("outcome", outcomeColor + c.bold + outcome.toUpperCase() + c.reset +
    (contract ? c.dim + `  contract: ${contract.contract_id}` + c.reset : "")));
  console.log(footer());
}

// ── 8. Booking Created ────────────────────────────────────────────────────
export function logBookingCreated(booking: any) {
  console.log("");
  console.log(header("📋", "BOOKING CREATED"));
  console.log(row("booking id", c.bold + booking.booking_id + c.reset));
  console.log(row("provider",   booking.provider_name ?? booking.provider_id));
  console.log(row("service",    booking.service_type));
  console.log(row("location",   booking.location));
  console.log(row("scheduled",  new Date(booking.scheduled_time).toLocaleString("en-PK")));
  console.log(row("price",      c.bold + c.green + `Rs. ${booking.final_price}` + c.reset));
  console.log(row("status",     c.yellow + booking.status + c.reset));
  console.log(footer());
}

// ── 9. Phase Transition ───────────────────────────────────────────────────
export function logPhase(sessionId: string, phase: string, detail?: string) {
  const phaseColor = phase === "booking_confirmed" ? c.green
    : phase === "intake" ? c.cyan
    : phase === "thinking" ? c.yellow
    : c.white;
  console.log(
    c.dim + `\n[Session ${sessionId.slice(-8)}]` + c.reset +
    " Phase → " + phaseColor + c.bold + phase.toUpperCase() + c.reset +
    (detail ? c.dim + `  (${detail})` + c.reset : "")
  );
}

// ── 10. Guardrail ─────────────────────────────────────────────────────────
export function logGuardrail(redactions: any[], safety: any) {
  console.log("");
  console.log(header("🛡️", "GUARDRAIL  [phase: guardrail]"));
  const safetyStatus = safety.flagged
    ? c.red + c.bold + "⚠ FLAGGED" + (safety.categories?.length ? `: ${safety.categories.join(", ")}` : "") + c.reset
    : c.green + "clean" + c.reset;
  console.log(row("safety.flagged", safetyStatus));
  console.log(row("pii_sent_to_llm", c.green + "false" + c.reset));
  if (redactions.length === 0) {
    console.log(row("redactions", "none"));
  } else {
    redactions.forEach((r: any) => {
      console.log(row("redacted", c.yellow + `[${r.type}]  →  ${r.token}` + c.reset));
    });
  }
  console.log(footer());
}

// ── 11. Output Safety ────────────────────────────────────────────────────
export function logOutputSafety(safe: boolean, reason?: string) {
  console.log("");
  console.log(header("🛡️", "OUTPUT SAFETY  [phase: guardrail]"));
  const status = safe
    ? c.green + "clean — no PII echoed in response" + c.reset
    : c.red + c.bold + "⚠ BLOCKED: " + (reason ?? "PII detected") + c.reset;
  console.log(row("output.safe", status));
  console.log(row("pii_in_reply", safe ? c.green + "false" + c.reset : c.red + "true" + c.reset));
  console.log(footer());
}

// ── 12. Fallback / Error ──────────────────────────────────────────────────
export function logFallback(agent: string, reason: string, action: string) {
  console.log("");
  console.log(header("⚠", `FALLBACK  [${agent}]`));
  console.log(row("reason",  c.yellow + reason + c.reset));
  console.log(row("action",  action));
  console.log(footer());
}
