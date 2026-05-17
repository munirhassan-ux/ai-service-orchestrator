import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const bookingsFile = path.join(__dirname, "../../data/mock_bookings.json");
const scheduleFile = path.join(__dirname, "../../data/mock_schedule.json");
function readBookings() {
    try {
        return JSON.parse(fs.readFileSync(bookingsFile, "utf-8"));
    }
    catch {
        return { bookings: [] };
    }
}
function writeBookings(data) {
    fs.writeFileSync(bookingsFile, JSON.stringify(data, null, 2));
}
function readSchedule() {
    try {
        return JSON.parse(fs.readFileSync(scheduleFile, "utf-8"));
    }
    catch {
        return {};
    }
}
function writeSchedule(data) {
    fs.writeFileSync(scheduleFile, JSON.stringify(data, null, 2));
}
function generateBookingId() {
    const date = new Date().toISOString().slice(0, 10).replace(/-/g, "");
    const seq = String(readBookings().bookings.length + 1).padStart(4, "0");
    return `BK-${date}-${seq}`;
}
function getScheduledTime(preferredTime, providerId, existingSchedule) {
    const now = new Date();
    const tomorrow = new Date(now);
    tomorrow.setDate(now.getDate() + 1);
    const timeMap = {
        asap: new Date(now.getTime() + 2 * 60 * 60 * 1000),
        today_morning: new Date(new Date(now).setHours(10, 0, 0, 0)),
        today_afternoon: new Date(new Date(now).setHours(14, 0, 0, 0)),
        today_evening: new Date(new Date(now).setHours(18, 0, 0, 0)),
        tomorrow_morning: new Date(new Date(tomorrow).setHours(10, 0, 0, 0)),
        tomorrow_afternoon: new Date(new Date(tomorrow).setHours(14, 0, 0, 0)),
        this_week: new Date(new Date(tomorrow).setHours(10, 0, 0, 0)),
        flexible: new Date(new Date(tomorrow).setHours(10, 0, 0, 0)),
    };
    let baseTime = (timeMap[preferredTime] || timeMap.tomorrow_morning);
    // Basic collision avoidance: if slot taken, move forward by 2 hours
    const providerSlots = existingSchedule[providerId] || [];
    let finalTime = baseTime.toISOString();
    while (providerSlots.some(s => s === finalTime || s.startsWith(finalTime))) {
        baseTime = new Date(baseTime.getTime() + 2 * 60 * 60 * 1000);
        finalTime = baseTime.toISOString();
    }
    return finalTime;
}
export function softLockSlot(providerId, preferredTime, sessionId) {
    const schedule = readSchedule();
    const slotTime = getScheduledTime(preferredTime, providerId, schedule);
    if (!schedule[providerId])
        schedule[providerId] = [];
    schedule[providerId].push(`${slotTime}::soft_locked::${sessionId}`);
    writeSchedule(schedule);
    console.log(`[BookingSimulator] Soft-locked slot ${slotTime} for provider ${providerId}, session ${sessionId}`);
    return slotTime;
}
export function releaseSoftLock(sessionId) {
    const schedule = readSchedule();
    let modified = false;
    for (const providerId in schedule) {
        const originalLen = schedule[providerId].length;
        schedule[providerId] = schedule[providerId].filter((slot) => !slot.includes(`::soft_locked::${sessionId}`));
        if (schedule[providerId].length !== originalLen) {
            modified = true;
        }
    }
    if (modified) {
        writeSchedule(schedule);
        console.log(`[BookingSimulator] Released soft-locks for session ${sessionId}`);
    }
}
export function convertSoftLockToHardLock(sessionId) {
    const schedule = readSchedule();
    let modified = false;
    for (const providerId in schedule) {
        schedule[providerId] = schedule[providerId].map((slot) => {
            if (slot.includes(`::soft_locked::${sessionId}`)) {
                modified = true;
                return slot.split("::")[0];
            }
            return slot;
        });
    }
    if (modified) {
        writeSchedule(schedule);
        console.log(`[BookingSimulator] Converted soft-locks to hard-locks for session ${sessionId}`);
    }
}
function getConfirmationMessage(booking, language) {
    if (language === "roman_urdu" || language === "mixed") {
        return `Booking confirm ho gayi! ${booking.provider_name} aap ke paas ${booking.location} mein ${new Date(booking.scheduled_time).toLocaleString("en-PK")} ko pohunchen ge. Booking ID: ${booking.booking_id}. Total: Rs. ${booking.final_price}.`;
    }
    return `Booking confirmed! ${booking.provider_name} will arrive at ${booking.location} on ${new Date(booking.scheduled_time).toLocaleString("en-PK")}. Booking ID: ${booking.booking_id}. Total: Rs. ${booking.final_price}.`;
}
function getChecklist(serviceType) {
    const checklists = {
        ac_repair: ["Diagnose the issue", "Complete repair", "Test AC running", "Clean up area", "Show result to customer"],
        ac_installation: ["Inspect mounting location", "Install AC unit", "Connect wiring", "Test cooling", "Clean up area", "Show result to customer"],
        electrician: ["Identify fault", "Complete electrical work", "Test all connections", "Clean up area"],
        plumber: ["Diagnose leak/blockage", "Complete repair", "Test water flow", "Clean up area"],
        cleaning: ["Clean all surfaces", "Vacuum/mop floors", "Clean bathrooms", "Remove trash", "Final inspection"],
        default: ["Complete the job", "Test/verify work", "Clean up area", "Show result to customer"],
    };
    const items = checklists[serviceType] || checklists.default;
    return items.map((item) => ({ item, completed: false }));
}
export function createBooking(intent, provider, priceQuote, finalPrice, negotiationThreadId = null, customerId = "customer_001") {
    const data = readBookings();
    const schedule = readSchedule();
    const before = { bookings_count: data.bookings.length };
    const scheduledTime = getScheduledTime(intent.preferred_time, provider.id, schedule);
    const bookingId = generateBookingId();
    // Block the slot in schedule
    if (!schedule[provider.id])
        schedule[provider.id] = [];
    schedule[provider.id].push(scheduledTime);
    writeSchedule(schedule);
    // Reminder = 1 hour before
    const reminderTime = new Date(new Date(scheduledTime).getTime() - 60 * 60 * 1000).toISOString();
    const booking = {
        booking_id: bookingId,
        provider_id: provider.id,
        provider_name: provider.name,
        customer_id: customerId,
        service_type: intent.service_type,
        location: intent.location,
        scheduled_time: scheduledTime,
        status: "confirmed",
        final_price: finalPrice,
        price_quote: priceQuote,
        negotiation_thread_id: negotiationThreadId,
        confirmation_message: "",
        reminder_scheduled_at: reminderTime,
        checklist: getChecklist(intent.service_type),
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        state_history: [{ status: "confirmed", timestamp: new Date().toISOString() }],
    };
    booking.confirmation_message = getConfirmationMessage(booking, intent.language);
    data.bookings.push(booking);
    writeBookings(data);
    const after = { bookings_count: data.bookings.length, latest_booking: bookingId };
    console.log(`[BookingSimulator] Created: ${bookingId} | Provider: ${provider.name} | Price: Rs. ${finalPrice}`);
    return { booking, before, after };
}
// Update booking status (state machine)
export function updateBookingStatus(bookingId, newStatus) {
    const data = readBookings();
    const booking = data.bookings.find((b) => b.booking_id === bookingId);
    if (!booking)
        throw new Error(`Booking ${bookingId} not found`);
    booking.status = newStatus;
    booking.updated_at = new Date().toISOString();
    booking.state_history.push({ status: newStatus, timestamp: new Date().toISOString() });
    writeBookings(data);
    console.log(`[BookingSimulator] Status updated: ${bookingId} → ${newStatus}`);
    return booking;
}
// Complete checklist item
export function completeChecklistItem(bookingId, itemIndex) {
    const data = readBookings();
    const booking = data.bookings.find((b) => b.booking_id === bookingId);
    if (!booking)
        throw new Error(`Booking ${bookingId} not found`);
    if (booking.checklist[itemIndex]) {
        booking.checklist[itemIndex].completed = true;
    }
    const allComplete = booking.checklist.every((item) => item.completed);
    if (allComplete) {
        booking.status = "completed";
        booking.state_history.push({ status: "completed", timestamp: new Date().toISOString() });
    }
    booking.updated_at = new Date().toISOString();
    writeBookings(data);
    return booking;
}
export function getBooking(bookingId) {
    return readBookings().bookings.find((b) => b.booking_id === bookingId);
}
//# sourceMappingURL=bookingSimulator.js.map