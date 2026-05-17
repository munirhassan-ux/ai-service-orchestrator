#!/bin/bash
echo "=== TESTING SCENARIO 1: HAPPY PATH ==="

# 1. Create Session
echo "Creating session..."
SESSION_RES=$(curl -s -X POST http://localhost:3000/api/session/create -H "Content-Type: application/json" -d '{"customer_id": "customer_001"}')
echo "Session response: $SESSION_RES"
SESSION_ID=$(echo $SESSION_RES | grep -o '"session_id":"[^"]*' | grep -o '[^"]*$')
echo "Session ID extracted: $SESSION_ID"

# 2. Trigger Intake
echo -e "\nTriggering Plumber Intake..."
INTAKE_RES=$(curl -s -X POST http://localhost:3000/api/orchestrate -H "Content-Type: application/json" -d "{\"input\": \"Plumber wanted in G-11 tomorrow evening\", \"session_id\": \"$SESSION_ID\"}")
echo "Intake response: $INTAKE_RES"
THREAD_ID=$(echo $INTAKE_RES | grep -o '"negotiation_thread_id":"[^"]*' | grep -o '[^"]*$')
echo "Thread ID extracted: $THREAD_ID"

# 3. Customer counter-offers Rs. 1400 (which is close to Rs. 1500 base, so it auto-accepts!)
echo -e "\nCustomer counter-offers Rs. 1400..."
COUNTER_RES=$(curl -s -X POST http://localhost:3000/api/orchestrate -H "Content-Type: application/json" -d "{\"input\": \"1400 PKR mein kar do yaara\", \"session_id\": \"$SESSION_ID\"}")
echo "Counter response: $COUNTER_RES"

# 4. Equipment verification (Acknowledged!)
echo -e "\nCustomer acknowledges equipment..."
ACK_RES=$(curl -s -X POST http://localhost:3000/api/orchestrate -H "Content-Type: application/json" -d "{\"input\": \"Haan equipment hai meray pas\", \"session_id\": \"$SESSION_ID\"}")
echo "Final response: $ACK_RES"
echo -e "\n=== SCENARIO 1 TEST COMPLETED ==="
