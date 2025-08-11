#!/bin/bash

USER="<BMC_USERNAME>"
PASSWORD="<BMC_PASSWORD>"
START_IP=<START_IP>
END_IP=<END_IP>

for i in $(seq $START_IP $END_IP); do
    IP="<IP_PREFIX>.$i"
    echo "$IP:"
    ipmitool -I lanplus -H "$IP" -U "$USER" -P "$PASSWORD" mc info 2>/dev/null | grep "Firmware Revision"
    echo
done

