export function calculatePrice(intent, provider, allProviders, userJobCount = 0) {
    const roundToNearest10 = (n) => Math.round(n / 10) * 10;
    // Exact Charge Calculations:
    // travel_distance_km = haversine(provider.lat, provider.lng, customer.lat, customer.lng)
    // travel_charges = travel_distance_km * provider.charges.travel_rate
    // on_demand_charges = service_fee * (0.15 for high / 0.30 for emergency)
    // total = service_fee + travel_charges + on_demand_charges
    // Base rate (PKR per hour)
    const base_rate = provider.charges.base_rate;
    const travel_rate = provider.charges.travel_rate || 30;
    // Let's assume estimated duration of 2 hours for all calculations.
    const estimated_hours = 2.0;
    const service_fee = roundToNearest10(base_rate * estimated_hours);
    // Travel charges
    const travel_distance_km = provider.distance_km;
    const travel_charges = roundToNearest10(travel_distance_km * travel_rate);
    // On demand charges based on urgency
    let on_demand_charges = 0;
    const lowerUrgency = (intent.urgency || "low").toLowerCase();
    if (lowerUrgency === "high" || lowerUrgency === "emergency") {
        const multiplier = lowerUrgency === "emergency" ? 0.30 : 0.15;
        on_demand_charges = roundToNearest10(service_fee * multiplier);
    }
    // Total calculation
    const total = roundToNearest10(service_fee + travel_charges + on_demand_charges);
    // Ranges for backward-compatibility with UI
    const min_total = roundToNearest10(total * 0.95);
    const max_total = roundToNearest10(total * 1.05);
    const breakdown_text = [
        `Base Service Fee: Rs. ${service_fee} (Estimated 2 hours)`,
        `Travel Charges (${provider.distance_km}km): Rs. ${travel_charges}`,
        on_demand_charges > 0 ? `On-demand Surcharge: Rs. ${on_demand_charges}` : null,
        `─────────────────────────────`,
        `Total Charges: Rs. ${total}`,
    ].filter(Boolean).join("\n");
    const fairness_note = "Standard flat-rate pricing applied, incorporating travel rate and urgency surge.";
    return {
        base_rate,
        distance_fee: travel_charges,
        urgency_surcharge: on_demand_charges,
        complexity_premium: 0,
        loyalty_discount: 0,
        surge_multiplier: 1.0,
        surge_active: false,
        visit_fee: 0,
        hours_min: estimated_hours,
        hours_max: estimated_hours,
        min_total,
        max_total,
        total,
        min_rate_total: min_total,
        floor_min: roundToNearest10(total * 0.9),
        floor_max: roundToNearest10(total * 1.1),
        industry_standard_min: roundToNearest10(service_fee * 0.8),
        industry_standard_max: roundToNearest10(service_fee * 1.3),
        currency: "PKR",
        breakdown_text,
        fairness_note,
    };
}
//# sourceMappingURL=pricingEngine.js.map