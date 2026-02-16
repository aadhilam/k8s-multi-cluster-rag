#!/usr/bin/env bash

# Check if both arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <kubeconfig_path> <cluster_name>"
    exit 1
fi

KUBECONFIG_PATH=$1
CLUSTER_NAME=$2  # Currently not used in the kubectl command, but kept for consistency

# How many attempts to make (10 minutes / 5 seconds = 120 attempts)
MAX_ATTEMPTS=200
# Interval between checks in seconds
INTERVAL=5

for i in $(seq 1 "$MAX_ATTEMPTS"); do
  # Retrieve the expiry date (in ISO8601 format) from the licensekey
  EXPIRY=$(
    kubectl --kubeconfig "$KUBECONFIG_PATH" \
            get licensekey default -o json 2>/dev/null \
      | jq -r '.status.expiry' 2>/dev/null
  )

  # If the command returned empty, keep retrying
  if [ -z "$EXPIRY" ]; then
    sleep "$INTERVAL"
    continue
  fi

  # If the expiry field is null, treat it as a pass (e.g. no expiry set)
  if [ "$EXPIRY" = "null" ]; then
    echo "License expiry returned null (no expiry set). Exiting successfully."
    exit 0
  fi

  # Parse ISO8601 date to epoch (works on both macOS/BSD and GNU date)
  if date --version >/dev/null 2>&1; then
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null)
  else
    EXPIRY_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$EXPIRY" +%s 2>/dev/null)
    [ -z "$EXPIRY_EPOCH" ] && EXPIRY_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$EXPIRY" +%s 2>/dev/null)
  fi
  CURRENT_EPOCH=$(date +%s)

  # If we successfully parsed an integer from EXPIRY_EPOCH
  if [[ "$EXPIRY_EPOCH" =~ ^[0-9]+$ ]]; then
    if [ "$EXPIRY_EPOCH" -gt "$CURRENT_EPOCH" ]; then
      echo "License expiry date ($EXPIRY) is in the future. Exiting successfully."
      exit 0
    fi
  fi

  # Wait for the specified interval before the next check
  sleep "$INTERVAL"
done

# If we reach here, we never found a future expiry date within 10 minutes
echo "License is not valid or has expired within 10 minutes of checking."
exit 1