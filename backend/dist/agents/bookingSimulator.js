import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
import { pushNotification } from "../notifications.js";
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
    return `SVC-${date}-${seq}`;
}
// Utility to update provider record in mock_providers.json
export function updateProviderInFile(providerId, updates) {
    const filePath = path.join(__dirname, "../../data/mock_providers.json");
    try {
        const providers = JSON.parse(fs.readFileSync(filePath, "utf-8"));
        const idx = providers.findIndex((p) => p.provider_id === providerId || p.id === providerId);
        if (idx !== -1) {
            providers[idx] = { ...providers[idx], ...updates };
            fs.writeFileSync(filePath, JSON.stringify(providers, null, 2));
            console.log(`[BookingSimulator] Saved provider updates for ${providerId} to file:`, updates);
        }
    }
    catch (err) {
        console.error(`[BookingSimulator] Error saving provider updates:`, err);
    }
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
// Approximate coordinate mappings for GPS movement simulation
const areaCoords = {
    "g-13": { lat: 33.6844, lng: 73.0479 },
    "g-11": { lat: 33.6938, lng: 73.0551 },
    "g-10": { lat: 33.6952, lng: 73.0621 },
    "g-9": { lat: 33.6987, lng: 73.0667 },
    "g-14": { lat: 33.6699, lng: 73.0342 },
    "g-15": { lat: 33.6601, lng: 73.0219 },
    "f-10": { lat: 33.7025, lng: 73.0122 },
    "f-11": { lat: 33.7098, lng: 73.0229 },
    "f-7": { lat: 33.7196, lng: 73.0551 },
    "f-8": { lat: 33.7156, lng: 73.0449 },
    "e-11": { lat: 33.7290, lng: 73.0130 },
    "i-8": { lat: 33.6715, lng: 73.0837 },
    "i-10": { lat: 33.6741, lng: 73.0721 },
    "b-17": { lat: 33.7595, lng: 72.9872 },
    "dha": { lat: 33.5355, lng: 73.1218 },
    "dha phase 2": { lat: 33.5412, lng: 73.1189 },
};
function getAreaCoords(location) {
    const key = location.toLowerCase().trim();
    for (const [area, coords] of Object.entries(areaCoords)) {
        if (key.includes(area) || area.includes(key))
            return coords;
    }
    return { lat: 33.6844, lng: 73.0479 }; // Default: G-13
}
export function createBooking(intent, provider, priceQuote, finalPrice, negotiationThreadId = null, customerId = "customer_001") {
    const data = readBookings();
    const schedule = readSchedule();
    const before = { bookings_count: data.bookings.length };
    const scheduledTime = getScheduledTime(intent.preferred_time, provider.provider_id, schedule);
    const bookingId = generateBookingId();
    // Block the slot in schedule
    if (!schedule[provider.provider_id])
        schedule[provider.provider_id] = [];
    schedule[provider.provider_id].push(scheduledTime);
    writeSchedule(schedule);
    // Reminder = 1 hour before
    const reminderTime = new Date(new Date(scheduledTime).getTime() - 60 * 60 * 1000).toISOString();
    // Setup GPS starting coords
    const customerCoords = getAreaCoords(intent.location);
    const providerCoords = provider.location || { latitude: 33.6844, longitude: 73.0479 };
    // Generate JOB DETAIL object with status = PENDING_PROVIDER
    const booking = {
        booking_id: bookingId,
        provider_id: provider.provider_id,
        provider_name: provider.name,
        customer_id: customerId,
        service_type: intent.service_type,
        location: intent.location,
        scheduled_time: scheduledTime,
        status: "PENDING_PROVIDER",
        final_price: finalPrice,
        price_quote: priceQuote,
        negotiation_thread_id: negotiationThreadId,
        confirmation_message: "",
        reminder_scheduled_at: reminderTime,
        checklist: getChecklist(intent.service_type),
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        state_history: [{ status: "PENDING_PROVIDER", timestamp: new Date().toISOString() }],
        current_lat: providerCoords.latitude,
        current_lng: providerCoords.longitude,
        customer_lat: customerCoords.lat,
        customer_lng: customerCoords.lng,
        distance_meters: Math.round(provider.distance_km * 1000),
    };
    booking.confirmation_message = getConfirmationMessage(booking, intent.language);
    data.bookings.push(booking);
    writeBookings(data);
    const after = { bookings_count: data.bookings.length, latest_booking: bookingId };
    console.log(`[BookingSimulator] Created: ${bookingId} | Provider: ${provider.name} | Price: Rs. ${finalPrice}`);
    pushNotification("PROVIDER", bookingId, "incoming_job", "Naya Kaam! 👷", `Naya ${intent.service_type} job available ${intent.location} mein. Tap to view details!`);
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
    if (newStatus === "ACCEPTED") {
        pushNotification("CUSTOMER", bookingId, "accepted", "Kaam Accept Ho Gaya! ✅", `${booking.provider_name} ne aap ka request accept kar liya hai.`);
    }
    else if (newStatus === "ARRIVING") {
        pushNotification("CUSTOMER", bookingId, "on_the_way", "Provider Raste Mein Hai! 🛵", `${booking.provider_name} raste mein hai.`);
    }
    else if (newStatus === "COMPLETED") {
        pushNotification("CUSTOMER", bookingId, "completed", "Kaam Mukammal! 🎉", `${booking.provider_name} ne kaam poora kar diya hai. Please rate karein!`);
    }
    else if (newStatus === "CANCELLED_PROVIDER") {
        pushNotification("CUSTOMER", bookingId, "cancelled", "Kaam Cancel Ho Gaya ⚠️", `${booking.provider_name} ne booking cancel kar di hai.`);
    }
    // Increment/Decrement Provider Active Jobs when state changes
    if (newStatus === "ACCEPTED") {
        // Increment active jobs
        const filePath = path.join(__dirname, "../../data/mock_providers.json");
        try {
            const providers = JSON.parse(fs.readFileSync(filePath, "utf-8"));
            const p = providers.find((pr) => pr.provider_id === booking.provider_id);
            if (p) {
                updateProviderInFile(booking.provider_id, {
                    active_jobs: Math.min(p.capacity, (p.active_jobs || 0) + 1),
                });
            }
        }
        catch (e) {
            console.error(e);
        }
    }
    else if (newStatus === "COMPLETED" || newStatus === "CANCELLED_PROVIDER" || newStatus === "CANCELLED_CUSTOMER") {
        // Decrement active jobs
        const filePath = path.join(__dirname, "../../data/mock_providers.json");
        try {
            const providers = JSON.parse(fs.readFileSync(filePath, "utf-8"));
            const p = providers.find((pr) => pr.provider_id === booking.provider_id);
            if (p) {
                updateProviderInFile(booking.provider_id, {
                    active_jobs: Math.max(0, (p.active_jobs || 1) - 1),
                });
            }
        }
        catch (e) {
            console.error(e);
        }
    }
    return booking;
}
// Recalculates provider scores upon provider-driven cancellation
export function handleProviderCancellation(bookingId) {
    const booking = updateBookingStatus(bookingId, "CANCELLED_PROVIDER");
    const providerPath = path.join(__dirname, "../../data/mock_providers.json");
    try {
        const providers = JSON.parse(fs.readFileSync(providerPath, "utf-8"));
        const idx = providers.findIndex((p) => p.provider_id === booking.provider_id);
        if (idx !== -1) {
            const p = providers[idx];
            const totalCancellations = Math.round((p.cancellation_risk || 0) * (p.total_jobs || 10));
            const newCancellations = totalCancellations + 1;
            const newJobs = (p.total_jobs || 10) + 1;
            const newRisk = newCancellations / newJobs;
            updateProviderInFile(booking.provider_id, {
                cancellation_risk: Math.round(newRisk * 100) / 100,
                total_jobs: newJobs,
            });
        }
    }
    catch (err) {
        console.error(err);
    }
    return booking;
}
// Recalculates provider scores upon rating submission
export function submitBookingRating(bookingId, stars, actualArrivalTimeStr) {
    const data = readBookings();
    const booking = data.bookings.find((b) => b.booking_id === bookingId);
    if (!booking)
        throw new Error(`Booking ${bookingId} not found`);
    // Calculate on-time score: actual_arrival <= scheduled_arrival + 10 mins
    const actualArrival = new Date(actualArrivalTimeStr);
    const scheduledArrival = new Date(booking.scheduled_time);
    const isOnTime = actualArrival.getTime() <= (scheduledArrival.getTime() + 10 * 60 * 1000) ? 1 : 0;
    const providerPath = path.join(__dirname, "../../data/mock_providers.json");
    try {
        const providers = JSON.parse(fs.readFileSync(providerPath, "utf-8"));
        const idx = providers.findIndex((p) => p.provider_id === booking.provider_id);
        if (idx !== -1) {
            const p = providers[idx];
            const oldRating = p.rating || 4.5;
            const totalReviews = p.total_reviews || 10;
            const newRating = ((oldRating * totalReviews) + stars) / (totalReviews + 1);
            const oldOnTimeScore = p.on_time_score || 0.9;
            const totalJobs = p.total_jobs || 10;
            const newOnTimeScore = ((oldOnTimeScore * totalJobs) + isOnTime) / (totalJobs + 1);
            const totalCancellations = Math.round((p.cancellation_risk || 0) * totalJobs);
            const newCancellationRisk = totalCancellations / (totalJobs + 1);
            updateProviderInFile(booking.provider_id, {
                rating: Math.round(newRating * 100) / 100,
                total_reviews: totalReviews + 1,
                on_time_score: Math.round(newOnTimeScore * 100) / 100,
                cancellation_risk: Math.round(newCancellationRisk * 100) / 100,
                total_jobs: totalJobs + 1,
                active_jobs: Math.max(0, (p.active_jobs || 1) - 1),
            });
        }
    }
    catch (err) {
        console.error(err);
    }
    booking.status = "COMPLETED";
    booking.updated_at = new Date().toISOString();
    booking.state_history.push({ status: "COMPLETED", timestamp: new Date().toISOString() });
    writeBookings(data);
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
        booking.status = "COMPLETED";
        booking.state_history.push({ status: "COMPLETED", timestamp: new Date().toISOString() });
        // Decrement active jobs on complete
        const filePath = path.join(__dirname, "../../data/mock_providers.json");
        try {
            const providers = JSON.parse(fs.readFileSync(filePath, "utf-8"));
            const p = providers.find((pr) => pr.provider_id === booking.provider_id);
            if (p) {
                updateProviderInFile(booking.provider_id, {
                    active_jobs: Math.max(0, (p.active_jobs || 1) - 1),
                });
            }
        }
        catch (e) {
            console.error(e);
        }
    }
    booking.updated_at = new Date().toISOString();
    writeBookings(data);
    return booking;
}
export function getBooking(bookingId) {
    return readBookings().bookings.find((b) => b.booking_id === bookingId);
}
//# sourceMappingURL=bookingSimulator.js.map