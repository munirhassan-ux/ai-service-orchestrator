import { ParsedIntent } from "./intentParser.js";
import { RankedProvider } from "./providerMatcher.js";
import { PriceQuote } from "./pricingEngine.js";
export type BookingStatus = "PENDING_PROVIDER" | "ACCEPTED" | "ARRIVING" | "ARRIVED" | "IN_PROGRESS" | "COMPLETED" | "CANCELLED_PROVIDER" | "CANCELLED_CUSTOMER";
export interface Booking {
    booking_id: string;
    provider_id: string;
    provider_name: string;
    customer_id: string;
    service_type: string;
    location: string;
    scheduled_time: string;
    status: BookingStatus;
    final_price: number;
    price_quote: PriceQuote;
    negotiation_thread_id: string | null;
    confirmation_message: string;
    reminder_scheduled_at: string;
    checklist: {
        item: string;
        completed: boolean;
    }[];
    created_at: string;
    updated_at: string;
    state_history: {
        status: BookingStatus;
        timestamp: string;
    }[];
    current_lat?: number;
    current_lng?: number;
    customer_lat?: number;
    customer_lng?: number;
    distance_meters?: number;
}
export declare function updateProviderInFile(providerId: string, updates: Partial<any>): void;
export declare function softLockSlot(providerId: string, preferredTime: string, sessionId: string): string;
export declare function releaseSoftLock(sessionId: string): void;
export declare function convertSoftLockToHardLock(sessionId: string): void;
export declare function createBooking(intent: ParsedIntent, provider: RankedProvider, priceQuote: PriceQuote, finalPrice: number, negotiationThreadId?: string | null, customerId?: string): {
    booking: Booking;
    before: any;
    after: any;
};
export declare function updateBookingStatus(bookingId: string, newStatus: BookingStatus): Booking;
export declare function handleProviderCancellation(bookingId: string): Booking;
export declare function submitBookingRating(bookingId: string, stars: number, actualArrivalTimeStr: string): Booking;
export declare function completeChecklistItem(bookingId: string, itemIndex: number): Booking;
export declare function getBooking(bookingId: string): Booking | undefined;
//# sourceMappingURL=bookingSimulator.d.ts.map