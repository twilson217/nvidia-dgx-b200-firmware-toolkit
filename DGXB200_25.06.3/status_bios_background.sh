#!/bin/bash

LOG_FILE="bios_background_copy.log"
USER="<BMC_USERNAME>"
PASSWORD="<BMC_PASSWORD>"
START_IP=<START_IP>
END_IP=<END_IP>

for i in $(seq $START_IP $END_IP); do
    IP="<IP_PREFIX>.$i"

    # Exclude specified IP
    if [ "$IP" = "<SKIP_IP>" ]; then
        continue
    fi

    # Extract the correct block for this IP
    TASK_LINE=$(awk "/----- $IP -----/{p=1;next}/----- /{p=0}p" "$LOG_FILE" | grep '"Message":"A new task' | head -1)
    
    # Extract the number at the end of the .../Tasks/<number> string
    TASK_NUM=$(echo "$TASK_LINE" | grep -o '/redfish/v1/TaskService/Tasks/[0-9]\+' | awk -F/ '{print $NF}')
    
    if [[ -z "$TASK_NUM" ]]; then
        echo "$IP: Task not found"
        continue
    fi

    OUT=$(nvfwupd -t ip=$IP user=$USER password="$PASSWORD" show_update_progress -i $TASK_NUM 2>/dev/null | grep '"PercentComplete":')
    
    if [[ -n "$OUT" ]]; then
        echo "$IP: $OUT"
    else
        echo "$IP: PercentComplete not found"
    fi
done

