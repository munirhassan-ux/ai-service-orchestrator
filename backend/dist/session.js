import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
const __filename = fileURLToPath(import.meta.url);
const currDir = path.dirname(__filename);
const sessionsFile = path.join(currDir, "../data/sessions.json");
function readSessions() {
    try {
        if (!fs.existsSync(sessionsFile)) {
            const dir = path.dirname(sessionsFile);
            if (!fs.existsSync(dir))
                fs.mkdirSync(dir, { recursive: true });
            fs.writeFileSync(sessionsFile, JSON.stringify({ sessions: [] }, null, 2));
            return { sessions: [] };
        }
        return JSON.parse(fs.readFileSync(sessionsFile, "utf-8"));
    }
    catch {
        return { sessions: [] };
    }
}
function writeSessions(data) {
    const dir = path.dirname(sessionsFile);
    if (!fs.existsSync(dir))
        fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(sessionsFile, JSON.stringify(data, null, 2));
}
export function generateSessionId() {
    return `SESS-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
}
export function createSession(customerId, role = "customer") {
    const data = readSessions();
    const now = new Date();
    const expires = new Date(now.getTime() + 30 * 60 * 1000); // 30-min TTL
    const session = {
        session_id: generateSessionId(),
        customer_id: customerId,
        role,
        phase: role === "provider" ? "profile_setup" : "greeting",
        parsed_intent: null,
        matched_providers: [],
        providers_tried: [],
        current_provider_index: 0,
        price_quote: null,
        negotiation_thread_id: null,
        equipment_acknowledged: false,
        restart_count: 0,
        agreed_price_range: null,
        negotiation_round: 1,
        budget_floor_warned: false,
        provider_profile: null,
        provider_setup_step: 0,
        created_at: now.toISOString(),
        updated_at: now.toISOString(),
        expires_at: expires.toISOString(),
        active_booking_id: null,
    };
    data.sessions.push(session);
    writeSessions(data);
    return session;
}
export function getSession(sessionId) {
    const data = readSessions();
    const session = data.sessions.find((s) => s.session_id === sessionId);
    if (!session)
        return null;
    // Check expiry
    if (new Date() > new Date(session.expires_at)) {
        console.log(`[Session] Session ${sessionId} has expired.`);
        return null; // expired
    }
    return session;
}
export function updateSession(sessionId, updates) {
    const data = readSessions();
    const index = data.sessions.findIndex((s) => s.session_id === sessionId);
    if (index === -1) {
        throw new Error(`Session ${sessionId} not found`);
    }
    const now = new Date();
    const expires = new Date(now.getTime() + 30 * 60 * 1000); // refresh TTL on activity
    const session = data.sessions[index];
    const updatedSession = {
        ...session,
        ...updates,
        updated_at: now.toISOString(),
        expires_at: expires.toISOString(),
    };
    data.sessions[index] = updatedSession;
    writeSessions(data);
    return updatedSession;
}
//# sourceMappingURL=session.js.map