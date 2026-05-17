import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export interface TraceEvent {
  step?: number;
  agent?: string;
  model?: string;
  prompt_summary?: string;
  gemini_decision?: string;
  confidence?: number;
  input?: any;
  output?: any;
  duration_ms?: number;
  fallback_triggered?: boolean;
  phase_after?: string;
  [key: string]: any;
}

export function logTraceEvent(sessionId: string, event: TraceEvent) {
  try {
    const traceDir = path.join(__dirname, "../data/agent_traces");
    if (!fs.existsSync(traceDir)) {
      fs.mkdirSync(traceDir, { recursive: true });
    }
    const traceFile = path.join(traceDir, `${sessionId}.json`);
    let currentTrace: TraceEvent[] = [];
    if (fs.existsSync(traceFile)) {
      currentTrace = JSON.parse(fs.readFileSync(traceFile, "utf-8"));
    }
    currentTrace.push({
      timestamp: new Date().toISOString(),
      ...event
    });
    fs.writeFileSync(traceFile, JSON.stringify(currentTrace, null, 2));
  } catch (err) {
    console.error(`[TraceLogger] Error writing trace for ${sessionId}:`, err);
  }
}
