#!/bin/bash

USER="<BMC_USERNAME>"
PASSWORD="<BMC_PASSWORD>"
START_IP=<START_IP>
END_IP=<END_IP>

for i in $(seq $START_IP $END_IP); do
    IP="<IP_PREFIX>.$i"
    # Uncomment next two lines if you want to skip a specific IP as in previous scripts:
    # if [ "$IP" = "<SKIP_IP>" ]; then
    #     continue
    # fi
    echo "$IP:"
    curl -s -k -u "$USER:$PASSWORD" -H 'content-type:application/json' \
         -X GET "https://$IP/redfish/v1/Chassis/HGX_ERoT_BMC_0" | jq | grep BackgroundCopyStatus
    echo
done

