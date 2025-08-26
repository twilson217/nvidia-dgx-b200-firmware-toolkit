#!/bin/bash

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

LOG_FILE="bmc_background_copy.log"

# Function to extract IP addresses from bmc.yaml
get_ips_from_yaml() {
    if [[ ! -f "$SCRIPT_DIR/bmc.yaml" ]]; then
        echo "Error: bmc.yaml not found. Please run setup.sh first." >&2
        exit 1
    fi
    
    # Extract BMC_IP addresses from YAML file
    grep "BMC_IP:" "$SCRIPT_DIR/bmc.yaml" | sed 's/.*BMC_IP: *"\([^"]*\)".*/\1/' | grep -v "BMC_IP_SYSTEM"
}

# Get IP addresses from YAML
IPS=$(get_ips_from_yaml)

if [[ -z "$IPS" ]]; then
    echo "Error: No IP addresses found in bmc.yaml" >&2
    exit 1
fi

# Loop through each IP address
for IP in $IPS; do
    # Extract the correct block for this IP
    TASK_LINE=$(awk "/----- $IP -----/{p=1;next}/----- /{p=0}p" "$LOG_FILE" | grep '"Message":"A new task' | head -1)
    
    # Extract the number at the end of the .../Tasks/<number> string
    TASK_NUM=$(echo "$TASK_LINE" | grep -o '/redfish/v1/TaskService/Tasks/[0-9]\+' | awk -F/ '{print $NF}')
    
    if [[ -z "$TASK_NUM" ]]; then
        echo "$IP: Task not found"
        continue
    fi

    OUT=$(nvfwupd -t ip=$IP user=$BMC_USERNAME password="$BMC_PASSWORD" show_update_progress -i $TASK_NUM 2>/dev/null | grep '"PercentComplete":')
    
    if [[ -n "$OUT" ]]; then
        echo "$IP: $OUT"
    else
        echo "$IP: PercentComplete not found"
    fi
done

