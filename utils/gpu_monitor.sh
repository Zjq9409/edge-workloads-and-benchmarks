#!/bin/bash

# GPU Monitoring Script
# Usage: ./gpu_monitor.sh <output_csv> <device_id> <interval> <model_name> <batch_size> <output_dir>

OUTPUT_FILE="$1"
DEVICE_ID="$2"
INTERVAL="${3:-1}"
MODEL_NAME="${4:-unknown}"
BATCH_SIZE="${5:-0}"
OUTPUT_DIR="${6:-.}"

if [[ -z "$OUTPUT_FILE" ]] || [[ -z "$DEVICE_ID" ]]; then
    echo "Usage: $0 <output_csv> <device_id> [interval] [model_name] [batch_size] [output_dir]"
    exit 1
fi

# Plot script path
PLOT_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plot_gpu_metrics.py"
QMASSA_PARSER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/parse_qmassa.py"

# Cleanup and plot generation on exit
cleanup_and_plot() {
    # Kill sudo keepalive process if running
    if [[ -n "${SUDO_KEEPALIVE_PID}" ]] && kill -0 "${SUDO_KEEPALIVE_PID}" 2>/dev/null; then
        kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
    fi
    
    # Kill qmassa process if running
    if [[ -n "${QMASSA_PID}" ]] && kill -0 "${QMASSA_PID}" 2>/dev/null; then
        sudo kill "${QMASSA_PID}" 2>/dev/null || true
    fi
    
    echo ""
    echo "[GPU Monitor] Monitoring stopped, generating plots..."
    
    # Check if CSV file has data
    if [[ -f "$OUTPUT_FILE" ]]; then
        LINE_COUNT=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
        
        if [[ ${LINE_COUNT} -gt 1 ]]; then
            # Generate plots
            if [[ -f "$PLOT_SCRIPT" ]]; then
                if python3 "$PLOT_SCRIPT" "$OUTPUT_FILE" > /dev/null 2>&1; then
                    echo "[GPU Monitor] ✓ GPU metrics plots generated successfully"
                    echo "[GPU Monitor]   - ${OUTPUT_DIR}/gpu_metrics_main.png"
                    echo "[GPU Monitor]   - ${OUTPUT_DIR}/gpu_metrics_engines.png"
                else
                    echo "[GPU Monitor] ⚠ Failed to generate GPU metrics plots"
                fi
            else
                echo "[GPU Monitor] ⚠ Plot script not found: $PLOT_SCRIPT"
            fi
            
            # Calculate and display average metrics
            AVG_GPU_UTIL=$(awk -F',' 'NR>1 && $4 ~ /^[0-9]+(\.[0-9]+)?$/ {sum+=$4; count++} END {if(count>0) printf("%.2f", sum/count); else print "N/A"}' "$OUTPUT_FILE")
            AVG_GPU_POWER=$(awk -F',' 'NR>1 && $5 ~ /^[0-9]+(\.[0-9]+)?$/ {sum+=$5; count++} END {if(count>0) printf("%.2f", sum/count); else print "N/A"}' "$OUTPUT_FILE")
            AVG_GPU_FREQ=$(awk -F',' 'NR>1 && $6 ~ /^[0-9]+(\.[0-9]+)?$/ {sum+=$6; count++} END {if(count>0) printf("%.0f", sum/count); else print "N/A"}' "$OUTPUT_FILE")
            
            echo "[GPU Monitor] Average Metrics:"
            echo "[GPU Monitor]   GPU Utilization: ${AVG_GPU_UTIL}%"
            echo "[GPU Monitor]   GPU Power: ${AVG_GPU_POWER}W"
            echo "[GPU Monitor]   GPU Frequency: ${AVG_GPU_FREQ}MHz"
        else
            echo "[GPU Monitor] ⚠ No monitoring data collected"
        fi
    fi
    
    # Generate qmassa plots if JSON file exists
    if [[ -n "${USE_QMASSA}" ]] && [[ "${USE_QMASSA}" == true ]] && [[ -f "${QMASSA_JSON_FILE}" ]]; then
        echo ""
        echo "[GPU Monitor] Generating qmassa charts..."
        
        QMASSA_OUTPUT_PREFIX="${OUTPUT_DIR}/qmassa_charts"
        
        if sudo "${QMASSA_SCRIPT}" plot -j "${QMASSA_JSON_FILE}" -c meminfo,engines,freqs,power,temps -o "${QMASSA_OUTPUT_PREFIX}" > /dev/null 2>&1; then
            echo "[GPU Monitor] ✓ qmassa charts generated successfully"
            echo "[GPU Monitor]   SVG files: ${QMASSA_OUTPUT_PREFIX}_*.svg"
        else
            echo "[GPU Monitor] ⚠ Failed to generate qmassa charts"
        fi
    fi
    
    exit 0
}

# Register cleanup handler
trap cleanup_and_plot EXIT INT TERM

# Detect kernel version and choose monitoring tool
KERNEL_VERSION=$(uname -r)
USE_QMASSA=false

# Check if kernel is 6.14.0-37-generic
if [[ "$KERNEL_VERSION" == "6.14.0-37-generic" ]]; then
    USE_QMASSA=true
    QMASSA_SCRIPT="/home/intel/media_ai/edge-workloads-and-benchmarks/qmassa"
    QMASSA_JSON_FILE="${OUTPUT_DIR}/gpu_metrics_raw.json"
    
    if [[ ! -f "$QMASSA_SCRIPT" ]]; then
        echo "Error: qmassa script not found at $QMASSA_SCRIPT"
        echo "Falling back to xpu-smi only"
        USE_QMASSA=false
    fi
fi

# Metrics to collect (for xpu-smi)
METRICS="0,1,2,3,4,18,22,24,25,26,27,36"

# Initialize CSV with header if it doesn't exist
# Detect GPU type by checking xpu-smi header output
if [[ ! -f "$OUTPUT_FILE" ]]; then
    # Get the actual header from xpu-smi
    XPU_HEADER=$(sudo xpu-smi dump -d "$DEVICE_ID" -m "$METRICS" -n 1 2>/dev/null | grep "Timestamp" | head -n 1)
    
    # Add Model Name and Batch Size columns to the beginning
    echo "Model Name,Batch Size,${XPU_HEADER}" > "$OUTPUT_FILE"
    echo "[GPU Monitor] Initialized CSV with header from xpu-smi"
fi

# Start qmassa if enabled (runs in background continuously)
if [[ "$USE_QMASSA" == true ]]; then
    # Convert device_id (0) to PCI address format
    PCI_ADDR="0000:18:00.0"
    
    echo "[GPU Monitor] Starting qmassa monitoring..."
    # -m 1000: 1 second interval
    # -t: save to JSON file
    # -x: no TUI rendering
    sudo "$QMASSA_SCRIPT" -d "$PCI_ADDR" -m 1000 -t "$QMASSA_JSON_FILE" -x >/dev/null 2>&1 &
    QMASSA_PID=$!
    sleep 2  # Wait for qmassa to initialize
    echo "[GPU Monitor] qmassa started (PID: $QMASSA_PID), output: $QMASSA_JSON_FILE"
    
    # Keep sudo credentials alive for qmassa plot later
    (while true; do sudo -v; sleep 60; done) 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
fi

# Run xpu-smi monitoring loop (always runs)
echo "[GPU Monitor] Starting xpu-smi monitoring..."
while true; do
    # Get current timestamp
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Use xpu-smi for monitoring
    DATA=$(sudo xpu-smi dump -d "$DEVICE_ID" -m "$METRICS" -n 1 2>/dev/null | grep -v "Timestamp" | tail -n 1 | tr -s ' ' | sed 's/^ //g')
    
    if [[ -n "$DATA" ]]; then
        # Append to CSV with model name and batch size
        echo "${MODEL_NAME},${BATCH_SIZE},${DATA}" >> "$OUTPUT_FILE"
    fi
    
    sleep "$INTERVAL"
done
