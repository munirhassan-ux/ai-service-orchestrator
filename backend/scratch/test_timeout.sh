#!/bin/bash
echo "=== TESTING SCENARIO 3: PROVIDER TIMEOUT SKIP & WARM RESTART ==="

# 1. Create Session
SESSION_RES=$(curl -s -X POST http://localhost:3000/api/session/create -H "Content-Type: application/json" -d '{"customer_id": "customer_002"}')
SESSION_ID=$(echo $SESSION_RES | grep -o '"session_id":"[^"]*' | grep -o '[^"]*$')
echo "Created session: $SESSION_ID"

# 2. Intake Plumber
INTAKE_RES=$(curl -s -X POST http://localhost:3000/api/orchestrate -H "Content-Type: application/json" -d "{\"input\": \"AC Plumber needed G-11 right now\", \"session_id\": \"$SESSION_ID\"}")
echo -e "\nIntake response: $INTAKE_RES"

# 3. Simulate Timeout Skip!
echo -e "\n--- SIMULATING PROVIDER TIMEOUT SKIP ---"
TIMEOUT_RES=$(curl -s -X POST http://localhost:3000/api/negotiate/timeout -H "Content-Type: application/json" -d "{\"session_id\": \"$SESSION_ID\"}")
echo "Timeout skip response: $TIMEOUT_RES"

echo -e "\n=== SCENARIO 3 TEST COMPLETED ==="
