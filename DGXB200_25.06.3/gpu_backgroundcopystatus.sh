#!/bin/bash

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

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
    echo "$IP:"
    curl -s -k -u "$BMC_USERNAME:$BMC_PASSWORD" -H 'content-type:application/json' \
         -X GET "https://$IP/redfish/v1/Chassis/HGX_ERoT_BMC_0" | jq | grep BackgroundCopyStatus
    echo
done

