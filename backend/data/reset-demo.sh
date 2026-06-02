#!/bin/bash
echo '{"bookings":[]}' > mock_bookings.json
echo '{"sessions":[]}' > sessions.json
echo '{"schedule":{}}' > mock_schedule.json
rm -f agent_traces/*.json
echo "✓ Demo reset complete. All bookings, sessions, and traces cleared."
