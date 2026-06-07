import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname  = path.dirname(__filename);
const DB_FILE    = path.join(__dirname, "../../data/customer_abuse.json");

const BAN_AFTER_STRIKES  = 9;   // 3 full sessions of abuse before 24-hr cumulative ban
const BAN_DURATION_MS    = 24 * 60 * 60 * 1000;

interface AbuseRecord {
  strikes:      number;
  blocked_until: string | null; // ISO timestamp, null = not banned
  last_strike:  string;
}
type AbuseDB = Record<string, AbuseRecord>;

function read(): AbuseDB {
  try {
    if (!fs.existsSync(DB_FILE)) return {};
    return JSON.parse(fs.readFileSync(DB_FILE, "utf-8"));
  } catch { return {}; }
}

function write(db: AbuseDB): void {
  const dir = path.dirname(DB_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(DB_FILE, JSON.stringify(db, null, 2));
}

export function recordStrike(customerId: string): AbuseRecord {
  const db = read();
  const existing = db[customerId] ?? { strikes: 0, blocked_until: null, last_strike: "" };
  const newStrikes = existing.strikes + 1;
  const blockedUntil = newStrikes >= BAN_AFTER_STRIKES
    ? new Date(Date.now() + BAN_DURATION_MS).toISOString()
    : existing.blocked_until;

  const updated: AbuseRecord = {
    strikes:      newStrikes,
    blocked_until: blockedUntil,
    last_strike:  new Date().toISOString(),
  };
  db[customerId] = updated;
  write(db);
  return updated;
}

export function isCustomerBlocked(customerId: string): boolean {
  const db = read();
  const record = db[customerId];
  if (!record?.blocked_until) return false;
  // Auto-expire: if ban time has passed, treat as unblocked
  return new Date() < new Date(record.blocked_until);
}

export function getCustomerStrikes(customerId: string): number {
  const db = read();
  return db[customerId]?.strikes ?? 0;
}

export function getBanExpiryMessage(customerId: string): string {
  const db = read();
  const record = db[customerId];
  if (!record?.blocked_until) return "";
  const remaining = new Date(record.blocked_until).getTime() - Date.now();
  const hours = Math.ceil(remaining / (60 * 60 * 1000));
  return `Aap ka account ${hours} ghante ke liye block hai.`;
}
