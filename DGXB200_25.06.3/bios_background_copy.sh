#!/bin/bash

USER="<BMC_USERNAME>"
PASSWORD="<BMC_PASSWORD>"
CONTENT_TYPE="Content-Type: application/json"
POST_DATA='{
  "Targets": ["/redfish/v1/UpdateService/FirmwareInventory/HostBIOS_0"]
}'
END_IP=<END_IP>
START_IP=<START_IP>
LOG_FILE="bios_background_copy.log"

# Clear old log
> "$LOG_FILE"

for i in $(seq $START_IP $END_IP); do
    IP="<IP_PREFIX>.$i"
    if [ "$IP" = "<SKIP_IP>" ]; then
        continue
    fi
    echo "----- $IP -----" >> "$LOG_FILE"
    curl -k -u "$USER:$PASSWORD" \
         --request POST \
         --location "https://$IP/redfish/v1/UpdateService/Actions/Oem/NvidiaUpdateService.CommitImage" \
         --header "$CONTENT_TYPE" \
         --data "$POST_DATA" 2>&1 \
    >> "$LOG_FILE"
    echo -e "\n" >> "$LOG_FILE"
done
