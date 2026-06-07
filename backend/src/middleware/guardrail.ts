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
// CNIC: 42101-1234567-8 / 42101 1234567 8 / 4210112345678 (13 digits, optional separators)
const CNIC_RE = /\b\d{5}[-\s]?\d{7}[-\s]?\d\b/g;
// Standard email
const EMAIL_RE = /\b[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}\b/g;
// House / plot / flat number (not area codes like G-13)
const HOUSE_RE = /\b(house|makan|h\.?no\.?|plot|flat|apartment|apt)\s*(no\.?\s*|number\s*|#\s*)?\d+\b/gi;

const ABUSE_WORDS = [
  // English
  'bastard', 'fuck', 'shit', 'bitch', 'asshole', 'cunt', 'dick', 'piss',
  // Urdu/Hindi — strong
  'haramzada', 'haramzadi', 'harami', 'chutiya', 'madarchod', 'bhenchod', 'gaand', 'gandu',
  // Urdu/Hindi — mild but abusive in context
  'kaminey', 'kamina', 'kamini', 'suar', 'soor', 'kutte', 'kutta', 'kutiya',
  'sala', 'salay', 'ullu', 'gadha',
];

// Normalize leet speak and punctuation tricks so "sh!t", "f.u.c.k", "h4ramzada" are caught.
function normalizeLeet(text: string): string {
  return text
    .toLowerCase()
    .replace(/[@]/g,  'a')
    .replace(/[0]/g,  'o')
    .replace(/[1!|]/g, 'i')
    .replace(/[3]/g,  'e')
    .replace(/[4]/g,  'a')
    .replace(/[$5]/g, 's')
    .replace(/[7]/g,  't')
    // Remove punctuation/spaces injected between letters (f.u.c.k → fuck, f u c k → fuck)
    .replace(/([a-z])[.\-_*\s]+(?=[a-z])/g, '$1');
}

export function redact(text: string): GuardrailResult {
  let out = text;
  const redactions: RedactionEntry[] = [];
  const now = new Date().toISOString();

  // Safety scan — normalize leet speak first so "sh!t", "f.u.c.k", "h4ramzada" are caught
  const lower = normalizeLeet(text);
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
  EMAIL_RE.lastIndex = 0;
  if (PK_PHONE_RE.test(text)) return { safe: false, reason: 'Output echoed a phone number' };
  if (CNIC_RE.test(text))     return { safe: false, reason: 'Output echoed a CNIC' };
  if (EMAIL_RE.test(text))    return { safe: false, reason: 'Output echoed an email address' };
  return { safe: true };
}
