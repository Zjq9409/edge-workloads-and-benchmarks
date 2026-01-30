#!/bin/bash

# GPU Monitoring Script
# Usage: ./gpu_monitor.sh <output_csv> <device_id> <interval> <model_name> <batch_size>

OUTPUT_FILE="$1"
DEVICE_ID="$2"
INTERVAL="${3:-1}"
MODEL_NAME="${4:-unknown}"
BATCH_SIZE="${5:-0}"

if [[ -z "$OUTPUT_FILE" ]] || [[ -z "$DEVICE_ID" ]]; then
    echo "Usage: $0 <output_csv> <device_id> [interval] [model_name] [batch_size]"
    exit 1
fi

# Metrics to collect
METRICS="0,1,2,3,4,18,22,24"

# Initialize CSV with header if it doesn't exist
if [[ ! -f "$OUTPUT_FILE" ]]; then
    echo "Model Name,Batch Size,Timestamp,DeviceId,GPU Utilization (%),GPU Power (W),GPU Frequency (MHz),GPU Core Temp (°C),GPU Mem Temp (°C),GPU Memory Used (MiB),Compute Engine Util (%),Media Decoder Util (%)" > "$OUTPUT_FILE"
fi

# Run xpu-smi and parse output
while true; do
    # Get current timestamp
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Run xpu-smi and capture output (remove header, get data line)
    DATA=$(xpu-smi dump -d "$DEVICE_ID" -m "$METRICS" -n 1 2>/dev/null | grep -v "Timestamp" | tail -n 1 | tr -s ' ' | sed 's/^ //g')
    
    if [[ -n "$DATA" ]]; then
        # Append to CSV with model name and batch size
        echo "${MODEL_NAME},${BATCH_SIZE},${DATA}" >> "$OUTPUT_FILE"
    fi
    
    sleep "$INTERVAL"
done
