#!/usr/bin/env python3
"""
Generate mock providers JSON for Pakistani home services app.
Output: ~50,960 providers (728 sub-tehsils × 10 service types × 7 providers each)
"""

import csv
import json
import random
import math
import os

# ── Paths ──────────────────────────────────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_PATH   = os.path.join(SCRIPT_DIR, "sub_tehsils_pakistan.csv")
OUT_PATH   = os.path.join(SCRIPT_DIR, "mock_providers.json")

# ── Name pools ─────────────────────────────────────────────────────────────────
FIRST_NAMES = [
    "Muhammad","Ali","Ahmed","Hassan","Usman","Tariq","Bilal","Fahad","Imran",
    "Kashif","Waqar","Naveed","Zubair","Rashid","Sajid","Asif","Nadeem","Irfan",
    "Aamir","Khalid","Arif","Waseem","Shoaib","Faisal","Adnan","Hamza","Rizwan",
    "Kamran","Noman","Sohail","Junaid","Zahid","Ahsan","Salman","Jamal","Rafiq",
    "Nasir","Anwar","Akram","Tahir","Yasir","Umar","Rehan","Babar","Sameer",
    "Furqan","Iqbal","Asad","Zain","Haris","Waleed","Saad","Daniyal","Sharjeel","Arslan",
]

LAST_NAMES = [
    "Khan","Ahmed","Ali","Malik","Sheikh","Qureshi","Siddiqui","Abbasi","Chaudhry",
    "Rana","Nawaz","Raza","Mirza","Bukhari","Hashmi","Farooq","Hussain","Shah",
    "Ansari","Baig","Gillani","Javed","Karim","Mehmood","Niazi","Paracha","Rasheed",
    "Saleem","Toor","Waheed","Aslam","Bhatti","Gul","Lodhi",
]

SHOP_SUFFIXES = [
    "Services","Works","Workshop","Solutions","Center","Point","Pro",
    "Technical Services","Repair Shop","Experts",
]

# ── Service type definitions ───────────────────────────────────────────────────
SERVICE_TYPES = [
    {
        "job_role": "AC Technician",
        "expertise_variants": [
            ["ac_repair","ac_installation","ac_maintenance"],
            ["ac_repair","ac_maintenance"],
            ["ac_installation","ac_maintenance"],
        ],
        "base_rate_range": (500, 1200),
    },
    {
        "job_role": "Electrician",
        "expertise_variants": [
            ["electrician","wiring","fan_repair"],
            ["electrician","wiring"],
            ["electrician","generator_repair","panel_work"],
        ],
        "base_rate_range": (400, 900),
    },
    {
        "job_role": "Plumber",
        "expertise_variants": [
            ["plumber","pipe_fitting","drain_cleaning"],
            ["plumber","motor_repair","pipe_fitting"],
            ["plumber","drain_cleaning"],
        ],
        "base_rate_range": (400, 800),
    },
    {
        "job_role": "Carpenter",
        "expertise_variants": [
            ["carpenter","furniture_repair","door_fitting"],
            ["carpenter","cupboard_making"],
            ["carpenter","furniture_repair"],
        ],
        "base_rate_range": (500, 1000),
    },
    {
        "job_role": "Cleaner",
        "expertise_variants": [
            ["home_cleaning","sofa_cleaning","carpet_cleaning"],
            ["home_cleaning","deep_cleaning"],
            ["office_cleaning","home_cleaning"],
        ],
        "base_rate_range": (300, 700),
    },
    {
        "job_role": "Painter",
        "expertise_variants": [
            ["wall_painting","house_painting"],
            ["exterior_painting","interior_painting"],
            ["wall_painting","polish_work"],
        ],
        "base_rate_range": (500, 1000),
    },
    {
        "job_role": "Gas Technician",
        "expertise_variants": [
            ["gas_repair","gas_installation","geyser_repair"],
            ["gas_repair","stove_repair"],
            ["geyser_repair","gas_installation"],
        ],
        "base_rate_range": (400, 800),
    },
    {
        "job_role": "CCTV Technician",
        "expertise_variants": [
            ["cctv_installation","security_systems","cctv_repair"],
            ["cctv_installation","network_setup"],
            ["security_systems","cctv_repair"],
        ],
        "base_rate_range": (600, 1200),
    },
    {
        "job_role": "Mechanic",
        "expertise_variants": [
            ["car_repair","bike_repair","engine_work"],
            ["car_repair","puncture_repair"],
            ["bike_repair","general_mechanic"],
        ],
        "base_rate_range": (400, 900),
    },
    {
        "job_role": "Solar Technician",
        "expertise_variants": [
            ["solar_installation","solar_maintenance","inverter_repair"],
            ["solar_installation","panel_cleaning"],
            ["inverter_repair","solar_maintenance"],
        ],
        "base_rate_range": (800, 1500),
    },
]

PROVIDERS_PER_TYPE = 7


def weighted_rating() -> float:
    """Return a rating biased toward 4.0–4.8."""
    # Use a beta-like distribution mapped to [3.4, 5.0]
    # by summing two uniform samples (triangular-ish, peak in the middle-high area)
    r = random.uniform(3.4, 5.0) * 0.4 + random.uniform(3.4, 5.0) * 0.6
    # Clamp and round
    return round(min(max(r, 3.4), 5.0), 1)


def derive_on_time(rating: float) -> float:
    """on_time_score correlated with rating (higher rating → higher on_time)."""
    # Normalise rating to [0,1] over range [3.4, 5.0]
    norm = (rating - 3.4) / (5.0 - 3.4)
    base = 0.55 + norm * (0.99 - 0.55)
    jitter = random.uniform(-0.05, 0.05)
    return round(min(max(base + jitter, 0.55), 0.99), 2)


def derive_cancellation_risk(rating: float) -> float:
    """cancellation_risk inversely correlated with rating."""
    norm = (rating - 3.4) / (5.0 - 3.4)
    base = 0.25 - norm * (0.25 - 0.01)
    jitter = random.uniform(-0.03, 0.03)
    return round(min(max(base + jitter, 0.01), 0.25), 2)


def main():
    # Load CSV
    rows = []
    with open(CSV_PATH, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)

    print(f"Loaded {len(rows)} sub-tehsil rows from CSV.")

    providers = []
    counter = 0

    for row in rows:
        try:
            base_lat = float(row["sub_lat"])
            base_lng = float(row["sub_lng"])
        except (ValueError, KeyError):
            continue

        district_name = row.get("district_name", "Unknown").strip()
        tehsil        = row.get("tehsil", "").strip().title()

        for svc in SERVICE_TYPES:
            job_role         = svc["job_role"]
            expertise_opts   = svc["expertise_variants"]
            rate_lo, rate_hi = svc["base_rate_range"]

            for _ in range(PROVIDERS_PER_TYPE):
                counter += 1
                provider_id = f"p{counter:05d}"

                first = random.choice(FIRST_NAMES)
                last  = random.choice(LAST_NAMES)
                name  = f"{first} {last}"
                shop  = f"{name} {job_role} {random.choice(SHOP_SUFFIXES)}"

                lat = round(base_lat + random.uniform(-0.005, 0.005), 6)
                lng = round(base_lng + random.uniform(-0.005, 0.005), 6)

                availability = "online" if random.random() < 0.80 else "offline"

                base_rate   = random.randint(rate_lo, rate_hi)
                travel_rate = random.randint(20, 50)

                rating            = weighted_rating()
                on_time_score     = derive_on_time(rating)
                cancellation_risk = derive_cancellation_risk(rating)

                capacity     = random.randint(2, 5)
                total_reviews = random.randint(5, 500)
                total_jobs    = total_reviews + random.randint(0, 200)

                provider = {
                    "provider_id": provider_id,
                    "name": name,
                    "shop_name": shop,
                    "location": {"latitude": lat, "longitude": lng},
                    "city": district_name,
                    "city_area": tehsil,
                    "availability_status": availability,
                    "charges": {
                        "base_rate": base_rate,
                        "travel_rate": travel_rate,
                    },
                    "job_role": job_role,
                    "service_expertise": random.choice(expertise_opts),
                    "rating": rating,
                    "on_time_score": on_time_score,
                    "cancellation_risk": cancellation_risk,
                    "capacity": capacity,
                    "active_jobs": 0,
                    "total_reviews": total_reviews,
                    "total_jobs": total_jobs,
                }
                providers.append(provider)

    print(f"Generated {len(providers):,} providers. Writing to {OUT_PATH} …")

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(providers, f, ensure_ascii=False, separators=(",", ":"))

    size_bytes = os.path.getsize(OUT_PATH)
    size_mb    = size_bytes / (1024 * 1024)
    print(f"Done. File size: {size_mb:.1f} MB ({size_bytes:,} bytes)")
    print(f"Total providers written: {len(providers):,}")


if __name__ == "__main__":
    random.seed(42)
    main()
