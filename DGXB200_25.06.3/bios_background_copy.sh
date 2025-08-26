#!/bin/bash

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

CONTENT_TYPE="Content-Type: application/json"
POST_DATA='{
  "Targets": ["/redfish/v1/UpdateService/FirmwareInventory/HostBIOS_0"]
}'
LOG_FILE="bios_background_copy.log"

# Function to extract IP addresses from bmc.yaml
get_ips_from_yaml() {
    if [[ ! -f "$SCRIPT_DIR/bmc.yaml" ]]; then
        echo "Error: bmc.yaml not found. Please run setup.sh first." >&2
        exit 1
    fi
    
    # Extract BMC_IP addresses from YAML file
    grep "BMC_IP:" "$SCRIPT_DIR/bmc.yaml" | sed 's/.*BMC_IP: *"\([^"]*\)".*/\1/' | grep -v "BMC_IP_SYSTEM"
}

# Clear old log
> "$LOG_FILE"

# Get IP addresses from YAML
IPS=$(get_ips_from_yaml)

if [[ -z "$IPS" ]]; then
    echo "Error: No IP addresses found in bmc.yaml" >&2
    exit 1
fi

# Loop through each IP address
for IP in $IPS; do
    echo "----- $IP -----" >> "$LOG_FILE"
    curl -k -u "$BMC_USERNAME:$BMC_PASSWORD" \
         --request POST \
         --location "https://$IP/redfish/v1/UpdateService/Actions/Oem/NvidiaUpdateService.CommitImage" \
         --header "$CONTENT_TYPE" \
         --data "$POST_DATA" 2>&1 \
    >> "$LOG_FILE"
    echo -e "\n" >> "$LOG_FILE"
done
