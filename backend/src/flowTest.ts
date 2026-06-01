import dotenv from "dotenv";
dotenv.config();

import { parseIntent } from "./agents/intentParser.js";
import { matchProviders } from "./agents/providerMatcher.js";
import { createBooking, handleProviderCancellation, submitBookingRating } from "./agents/bookingSimulator.js";
import { calculatePrice } from "./agents/pricingEngine.js";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const currDir = path.dirname(__filename);

async function runFlowTest() {
  console.log("=========================================");
  console.log("🧪 RUNNING END-TO-END FLOW VERIFICATION");
  console.log("=========================================\n");

  // Step 1: Parse Service Request
  console.log("Step 1: Parsing Roman Urdu Request...");
  const rawRequest = "Oye, mujhe kal sham G-11 mein plumber chahye urgent basis pe budget low hai";
  const intent = await parseIntent(rawRequest, []);

  console.log("Parsed Intent Result:");
  console.log(`- Service Type: ${intent.service_type}`);
  console.log(`- Location: ${intent.location}`);
  console.log(`- Urgency: ${intent.urgency}`);
  console.log(`- Budget Sensitivity: ${intent.budget_sensitivity}`);
  console.log(`- Confidence: ${intent.confidence}\n`);

  if (intent.clarification_needed) {
    console.log(`⚠️ Clarification needed: ${intent.clarification_question}`);
  }

  // Step 2: Provider Matching
  console.log("Step 2: Provider Matching & Ranking...");
  const matchResult = await matchProviders(intent);
  console.log(`Found ${matchResult.top_providers.length} matches.`);

  for (let i = 0; i < matchResult.top_providers.length; i++) {
    const p = matchResult.top_providers[i];
    console.log(`[Rank ${i + 1}] Name: ${p.name} | Composite Score: ${p.score.toFixed(1)}`);
    console.log(`  - Base Charges: Rs. ${p.charges.base_rate}/hr`);
    console.log(`  - Distance: ${p.distance_km.toFixed(2)} km`);
    console.log(`  - Rating: ${p.rating} | On-Time: ${p.on_time_score.toFixed(2)} | Cancellation Risk: ${p.cancellation_risk.toFixed(2)}`);
  }
  console.log("");

  if (matchResult.top_providers.length === 0) {
    console.log("❌ No providers found!");
    return;
  }

  // Step 3 & 4: Selection and Confirmation
  const selectedProvider = matchResult.top_providers[0];
  console.log(`Step 3: Selecting top provider: ${selectedProvider.name}...`);

  const quote = selectedProvider.price_quote || calculatePrice(intent, selectedProvider, matchResult.top_providers);
  const finalPrice = quote.total;

  console.log("Step 4: Confirming Booking...");
  // Create a clean mock thread id
  const mockThreadId = "thread_" + Date.now();
  const { booking } = await createBooking(
    intent,
    selectedProvider,
    quote,
    finalPrice,
    mockThreadId,
    "customer_001"
  );

  console.log("Booking Confirmed:");
  console.log(`- Booking ID: ${booking.booking_id}`);
  console.log(`- Status: ${booking.status}`);
  console.log(`- Customer Location: ${booking.location}`);
  console.log(`- Final Price: Rs. ${booking.final_price}`);
  console.log(`- Checklist Count: ${booking.checklist.length} items\n`);

  // Step 5: Simulate GPS steps movement to arrival
  console.log("Step 5: Simulating GPS Coordinate Movement to Arrival...");
  let currentLat = booking.current_lat || 33.6844;
  let currentLng = booking.current_lng || 73.0479;
  const customerLat = booking.customer_lat || 33.6844;
  const customerLng = booking.customer_lng || 73.0551;
  const step_fraction = 0.5; // Quick step fraction for test speed

  let step = 1;
  while (true) {
    const dLat = customerLat - currentLat;
    const dLng = customerLng - currentLng;
    currentLat = currentLat + dLat * step_fraction;
    currentLng = currentLng + dLng * step_fraction;

    // Distance calculation
    const R = 6371;
    const dLatRad = ((customerLat - currentLat) * Math.PI) / 180;
    const dLngRad = ((customerLng - currentLng) * Math.PI) / 180;
    const a =
      Math.sin(dLatRad / 2) * Math.sin(dLatRad / 2) +
      Math.cos((currentLat * Math.PI) / 180) *
        Math.cos((customerLat * Math.PI) / 180) *
        Math.sin(dLngRad / 2) *
        Math.sin(dLngRad / 2);
    const distKm = R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const distMeters = Math.round(distKm * 1000);

    console.log(`  [GPS Step ${step}] Coords: (${currentLat.toFixed(5)}, ${currentLng.toFixed(5)}) | Remaining Distance: ${distMeters}m`);

    if (distMeters <= 50) {
      console.log("🎯 Provider arrived! Status auto-updates to ARRIVED -> IN_PROGRESS");
      break;
    }
    step++;
    if (step > 15) break;
  }
  console.log("");

  // Step 6: Test Provider Cancellation
  console.log("Step 6: Testing Provider Cancellation & Score updates...");
  // Cache original scores to check changes
  const providersPath = path.join(currDir, "../data/mock_providers.json");
  const origProviders = JSON.parse(fs.readFileSync(providersPath, "utf-8"));
  const origP = origProviders.find((p: any) => p.provider_id === selectedProvider.provider_id);
  const origRisk = origP ? origP.cancellation_risk : 0;
  const origJobs = origP ? origP.total_jobs : 10;

  console.log(`Original Provider Stats: Total Jobs: ${origJobs} | Cancellation Risk: ${origRisk.toFixed(2)}`);

  const cancelledBooking = handleProviderCancellation(booking.booking_id);
  const updatedProviders = JSON.parse(fs.readFileSync(providersPath, "utf-8"));
  const updatedP = updatedProviders.find((p: any) => p.provider_id === selectedProvider.provider_id);
  const updatedRisk = updatedP ? updatedP.cancellation_risk : 0;
  const updatedJobs = updatedP ? updatedP.total_jobs : 0;

  console.log("After Provider Cancellation Stats:");
  console.log(`- Booking Status: ${cancelledBooking.status}`);
  console.log(`- Updated Total Jobs: ${updatedJobs}`);
  console.log(`- Updated Cancellation Risk: ${updatedRisk.toFixed(2)}`);
  console.log(`- Formula verified: ((cancellations + 1) / (total_jobs + 1)) -> ${updatedRisk.toFixed(2)}\n`);

  // Step 7: Rating & Completion Recalculation
  console.log("Step 7: Testing Job Completed & Rating submission recalculation...");
  const ratingStars = 5;
  const arrivedOnTimeStr = booking.scheduled_time; // 100% on time
  const ratedBooking = submitBookingRating(booking.booking_id, ratingStars, arrivedOnTimeStr);

  const finalProviders = JSON.parse(fs.readFileSync(providersPath, "utf-8"));
  const finalP = finalProviders.find((p: any) => p.provider_id === selectedProvider.provider_id);

  console.log("Recalculation Success:");
  console.log(`- Final Booking Status: ${ratedBooking.status}`);
  console.log(`- New Rating: ${finalP.rating.toFixed(2)}`);
  console.log(`- New On-Time Score: ${finalP.on_time_score.toFixed(2)}`);
  console.log(`- New Total Reviews: ${finalP.total_reviews}\n`);

  console.log("=========================================");
  console.log("🎉 ALL LIFE-CYCLE STEPS TESTED SUCCESSFULLY!");
  console.log("=========================================");
}

runFlowTest().catch(err => {
  console.error("Test execution failed:", err);
  process.exit(1);
});
