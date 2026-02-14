#!/bin/bash

# Check if both arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <kubeconfig_path> <cluster_name>"
    exit 1
fi

KUBECONFIG_PATH=$1
CLUSTER_NAME=$2

# Verify kubeconfig file exists
if [ ! -f "$KUBECONFIG_PATH" ]; then
    echo "Error: Kubeconfig file not found at $KUBECONFIG_PATH"
    exit 1
fi

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    sudo apt-get update && sudo apt-get install -y jq
fi

# Calculate end time (current time + 10 minutes in seconds)
END_TIME=$(($(date +%s) + 600))  # 600 seconds = 10 minutes

echo "Starting API server status check for cluster: $CLUSTER_NAME"
echo "Using kubeconfig: $KUBECONFIG_PATH"
echo "Will check every 2 seconds for up to 10 minutes"

while [ $(date +%s) -lt $END_TIME ]; do
    # Get the apiserver status using the specified kubeconfig
    API_STATUS=$(KUBECONFIG=$KUBECONFIG_PATH kubectl get tigerastatus apiserver -o json | \
                jq -r '.status.conditions[] | select(.type=="Available") | .status')

    # Check if the command was successful
    if [ $? -ne 0 ]; then
        echo "[$CLUSTER_NAME] Error: Failed to get apiserver status"
        sleep 2
        continue
    fi

    # Convert the status to uppercase for case-insensitive comparison
    API_STATUS_UPPER=$(echo "$API_STATUS" | tr '[:lower:]' '[:upper:]')

    # Get current timestamp for logging
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    if [ "$API_STATUS_UPPER" = "TRUE" ]; then
        echo "[$TIMESTAMP][$CLUSTER_NAME] Success: API Server is available"
        
        # Also check if Degraded and Progressing are False
        DEGRADED_STATUS=$(KUBECONFIG=$KUBECONFIG_PATH kubectl get tigerastatus apiserver -o json | \
                         jq -r '.status.conditions[] | select(.type=="Degraded") | .status')
        PROGRESSING_STATUS=$(KUBECONFIG=$KUBECONFIG_PATH kubectl get tigerastatus apiserver -o json | \
                           jq -r '.status.conditions[] | select(.type=="Progressing") | .status')
        
        if [ "$(echo "$DEGRADED_STATUS" | tr '[:lower:]' '[:upper:]')" = "FALSE" ] && \
           [ "$(echo "$PROGRESSING_STATUS" | tr '[:lower:]' '[:upper:]')" = "FALSE" ]; then
            echo "[$TIMESTAMP][$CLUSTER_NAME] All conditions met: Available=True, Degraded=False, Progressing=False"
            exit 0
        else
            echo "[$TIMESTAMP][$CLUSTER_NAME] Warning: API Server is available but other conditions are not met"
            echo "[$TIMESTAMP][$CLUSTER_NAME] Degraded: $DEGRADED_STATUS, Progressing: $PROGRESSING_STATUS"
        fi
    else
        echo "[$TIMESTAMP][$CLUSTER_NAME] API Server is not yet available, checking again in 2 seconds..."
    fi
    
    sleep 2
done

echo "[$CLUSTER_NAME] Timeout: API Server did not become available within 10 minutes"
exit 1