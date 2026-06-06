// PII Redactor + Safety Filter — wraps every Gemini call.
// Raw PII never leaves the server. Redaction is logged per session.

export interface RedactionEntry {
  type: string;
  token: string;
  timestamp: string;
}

export interface GuardrailResult {
  text: string;
  redactions: RedactionEntry[];
  safety: { flagged: boolean; categories: string[] };
  pii_sent_to_llm: false;
}

// Pakistani phone: 03xx-xxxxxxx / +92-3xx-xxxxxxx / 0092-3xx-xxxxxxx
const PK_PHONE_RE = /(\+92|0092|0)([-\s]?)(3\d{2})([-\s]?)\d{7}/g;
// CNIC: 42101-1234567-8
const CNIC_RE = /\b\d{5}-\d{7}-\d\b/g;
// Standard email
const EMAIL_RE = /\b[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}\b/g;
// House / plot / flat number (not area codes like G-13)
const HOUSE_RE = /\b(house|makan|h\.?no\.?|plot|flat|apartment|apt)\s*[#\s]*\d+\b/gi;

const ABUSE_WORDS = [
  'bastard', 'fuck', 'shit', 'bitch', 'asshole',
  'haramzada', 'harami', 'chutiya', 'madarchod', 'bhenchod', 'gaand',
];

export function redact(text: string): GuardrailResult {
  let out = text;
  const redactions: RedactionEntry[] = [];
  const now = new Date().toISOString();

  // Safety scan (before redaction so we see the original wording)
  const lower = text.toLowerCase();
  const flaggedCategories: string[] = [];
  if (ABUSE_WORDS.some(w => lower.includes(w))) flaggedCategories.push('profanity');

  // Reset regex state (global regexes are stateful)
  PK_PHONE_RE.lastIndex = 0;
  CNIC_RE.lastIndex = 0;
  EMAIL_RE.lastIndex = 0;
  HOUSE_RE.lastIndex = 0;

  let phoneIdx = 0;
  out = out.replace(PK_PHONE_RE, () => {
    const token = `[PHONE_${++phoneIdx}]`;
    redactions.push({ type: 'phone', token, timestamp: now });
    return token;
  });

  let cnicIdx = 0;
  out = out.replace(CNIC_RE, () => {
    const token = `[CNIC_${++cnicIdx}]`;
    redactions.push({ type: 'cnic', token, timestamp: now });
    return token;
  });

  let emailIdx = 0;
  out = out.replace(EMAIL_RE, () => {
    const token = `[EMAIL_${++emailIdx}]`;
    redactions.push({ type: 'email', token, timestamp: now });
    return token;
  });

  let houseIdx = 0;
  out = out.replace(HOUSE_RE, () => {
    const token = `[ADDRESS_${++houseIdx}]`;
    redactions.push({ type: 'address', token, timestamp: now });
    return token;
  });

  return {
    text: out,
    redactions,
    safety: { flagged: flaggedCategories.length > 0, categories: flaggedCategories },
    pii_sent_to_llm: false,
  };
}

export function checkOutput(text: string): { safe: boolean; reason?: string } {
  PK_PHONE_RE.lastIndex = 0;
  CNIC_RE.lastIndex = 0;
  if (PK_PHONE_RE.test(text)) return { safe: false, reason: 'Output echoed a phone number' };
  if (CNIC_RE.test(text)) return { safe: false, reason: 'Output echoed a CNIC' };
  return { safe: true };
}
