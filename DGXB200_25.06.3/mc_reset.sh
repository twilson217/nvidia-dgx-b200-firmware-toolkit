#!/bin/bash

USER="<BMC_USERNAME>"
PASSWORD="<BMC_PASSWORD>"
START_IP=<START_IP>
END_IP=<END_IP>
LOG_FILE="mc_reset.log"

# Clear old log
> "$LOG_FILE"

for i in $(seq $START_IP $END_IP); do
    IP="<IP_PREFIX>.$i"
    if [ "$IP" = "<SKIP_IP>" ]; then
        continue
    fi
    echo "----- $IP -----" >> "$LOG_FILE"
    ipmitool -I lanplus -H "$IP" -U "$USER" -P "$PASSWORD" mc reset cold 2>&1 >> "$LOG_FILE"
    echo -e "\n" >> "$LOG_FILE"
done