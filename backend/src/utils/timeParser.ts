// Shared PKT-aware natural language time parser.
// Imported by bookingSimulator.ts and providerMatcher.ts to avoid circular deps.

export function parseNaturalLanguageTime(preferred: string): Date {
  if (/^\d{4}-\d{2}-\d{2}T/.test(preferred ?? "")) return new Date(preferred);

  const pkt = new Date(new Date().toLocaleString("en-US", { timeZone: "Asia/Karachi" }));
  const pktHour = pkt.getHours();
  const s = (preferred ?? "").toLowerCase().trim();

  function pktAt(base: Date, h: number): Date {
    const y  = base.getFullYear();
    const mo = String(base.getMonth() + 1).padStart(2, "0");
    const d  = String(base.getDate()).padStart(2, "0");
    const hr = String(h).padStart(2, "0");
    return new Date(`${y}-${mo}-${d}T${hr}:00:00+05:00`);
  }

  function todayAt(h: number): Date { return pktAt(pkt, h); }

  function daysFromNow(n: number, h: number): Date {
    const d = new Date(pkt);
    d.setDate(d.getDate() + n);
    return pktAt(d, h);
  }

  function nextWeekday(targetDay: number, h: number): Date {
    const d = new Date(pkt);
    const diff = ((targetDay - d.getDay()) + 7) % 7 || 7;
    d.setDate(d.getDate() + diff);
    return pktAt(d, h);
  }

  function extractHour(text: string): number | null {
    const m12 = text.match(/(\d{1,2})\s*(?:baje|am|pm|:00)/i);
    const m24 = text.match(/\b([01]?\d|2[0-3]):([0-5]\d)\b/);
    if (m24) return parseInt(m24[1]);
    if (m12) {
      let h = parseInt(m12[1]);
      const suffix = m12[0].slice(String(m12[1]).length).trim().toLowerCase();
      if (suffix === "pm" && h < 12) h += 12;
      else if (suffix === "am" && h === 12) h = 0;
      else {
        if (/shaam|evening/i.test(text) && h < 12) h += 12;
        if (/raat|night/i.test(text) && h < 9)    h += 12;
        if (/dopahar|afternoon/i.test(text) && h < 12) h += 12;
      }
      return h;
    }
    return null;
  }

  function periodHour(text: string): number {
    if (/subah|morning|صبح/.test(text))    return 10;
    if (/dopahar|afternoon|دوپہر/.test(text)) return 14;
    if (/shaam|evening|شام/.test(text))    return 18;
    if (/raat|night|رات/.test(text))       return 21;
    if (pktHour >= 6  && pktHour < 12) return 10;
    if (pktHour >= 12 && pktHour < 17) return 14;
    if (pktHour >= 17 && pktHour < 21) return 18;
    return 10;
  }

  const explicitHour = extractHour(s);
  const baseHour = explicitHour ?? periodHour(s);

  if (/\b(asap|abhi|foran|forun|dasti|dasty|jaldi(\s*se)?|turant|phoran|is\s*waqt|right\s*now|immediately|urgent|emergency|فوری|ابھی)\b/.test(s))
    return new Date(pkt.getTime() + 30 * 60 * 1000);  // 30 min → Active tab (hoursAway < 3)

  if (/^(aaj|today|آج)/.test(s)) {
    const h = explicitHour ?? (pktHour < 20 ? Math.max(pktHour + 2, 10) : 10);
    const t = todayAt(h);
    return t <= pkt ? daysFromNow(1, 10) : t;
  }

  if (/^(kal|tomorrow|کل)/.test(s) && !/parson|پرسوں/.test(s))
    return daysFromNow(1, baseHour);

  if (/parson|پرسوں/.test(s)) return daysFromNow(2, baseHour);

  const dayMap: [RegExp, number][] = [
    [/peer|پیر|monday/i,           1],
    [/mangal|منگل|tuesday/i,       2],
    [/budh|بدھ|wednesday/i,        3],
    [/jumeraat|جمعرات|thursday/i,  4],
    [/jummah|جمعہ|friday/i,        5],
    [/hafta|ہفتہ|saturday/i,       6],
    [/itwaar|اتوار|sunday/i,       0],
  ];
  for (const [re, day] of dayMap) {
    if (re.test(s)) return nextWeekday(day, baseHour);
  }

  if (s === "today_morning")      return todayAt(10);
  if (s === "today_afternoon")    return todayAt(14);
  if (s === "today_evening")      return todayAt(18);
  if (s === "tomorrow_morning")   return daysFromNow(1, 10);
  if (s === "tomorrow_afternoon") return daysFromNow(1, 14);

  // No day word detected but an hour may be present — try today first, fall to tomorrow if passed
  const t = todayAt(baseHour);
  return t > pkt ? t : daysFromNow(1, baseHour);
}

export function formatPKTTime(isoString: string): string {
  const d = new Date(isoString);
  return d.toLocaleString("en-US", {
    timeZone: "Asia/Karachi",
    weekday: "short",
    month:   "short",
    day:     "numeric",
    hour:    "numeric",
    minute:  "2-digit",
    hour12:  true,
  });
}
