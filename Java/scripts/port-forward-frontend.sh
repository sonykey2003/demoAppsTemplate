#!/usr/bin/env bash

echo "Forwarding frontend to http://localhost:9080"
echo "Press Ctrl+C to stop."

kubectl -n port-ops-demo port-forward svc/frontend 9080:9080
