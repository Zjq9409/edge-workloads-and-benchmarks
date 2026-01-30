#!/bin/bash

# Enhanced Pipeline Benchmark Script
# Run GStreamer pipeline in container and collect statistics

set -e

# 8个流，分成2个进程（每个进程4个流）
#./run_pipeline_benchmark.sh -v /home/dlstreamer/1280x720_25fps_medium.h265 -n 8 -P 2 -d GPU.0 -i 120

# 完整AI推理，48个流，6个进程（每个进程4个流）
#./run_pipeline_benchmark.sh -v /home/dlstreamer/1280x720_25fps_medium.h265 -m /home/dlstreamer/FP16/yolo11n.xml -n 48 -P 6 -d GPU.0 -b 32  -a  -p /home/dlstreamer/add_data.py -q localhost:1883 -i 120

# 默认单进程（与原来一样）
#./run_pipeline_benchmark.sh -v /home/dlstreamer/1280x720_25fps_medium.h265 -n 8 -d GPU.0 -i 120

#./run_pipeline_benchmark.sh -v /home/dlstreamer/1280x720_25fps_medium.h265 -m /home/intel/media_ai/edge-workloads-and-benchmarks_master/model-conversion/models/yolo11n/yolo11n_int8.xml -n 80 -P 6 -d GPU.1 -b 32  -a  -p /home/dlstreamer/add_data.py -q localhost:1883 -i 120
# ./run_pipeline_benchmark.sh -v /home/dlstreamer/1280x720_25fps_medium.h265 -m /home/dlstreamer/FP16/yolo11n.xml -n 48 -P 4 -d GPU.1 -b 64  -a  -p /home/dlstreamer/add_data.py -q localhost:1883 -i 120

# Configuration
IMAGE="intel/dlstreamer:2025.2.0-ubuntu24"
MOUNT_DIR="$(pwd)"
CONTAINER_NAME="benchmark_$$"
DURATION=120
TARGET_FPS=25
NUM_STREAMS=1NUM_PROCESSES=1DEVICE="GPU.0"
VIDEO_FILE="/home/dlstreamer/1280x720_25fps.h265"
MODEL_PATH="/home/intel/media_ai/edge-workloads-and-benchmarks/pipelines/light/detection/yolov11n_640x640/INT8/yolo11n.xml"
ENABLE_AI=false
MQTT_ADDRESS="localhost:1883"
PYTHON_MODULE=""

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  -v <video>         Video file path (default: 1280x720_25fps_medium.h265)
  -m <model>         Model XML path (default: /home/dlstreamer/FP16/yolo11n.xml)
  -n <num_streams>   Number of streams (default: 1)
  -P <num_processes> Number of gst-launch-1.0 processes (default: 1, streams distributed across processes)
  -d <device>        Device (e.g., GPU.0, GPU.1) (default: GPU.0)
  -g <gpu_card>      GPU card (e.g., card0, card1) (default: auto-detect)
  -i <duration>      Test duration in seconds (default: 120)
  -t <target_fps>    Target FPS for density calculation (default: 25)
  -b <batch_size>    Batch size (default: 1)
  -a                 Enable AI inference pipeline (gvadetect + gvatrack + metadata)
  -p <python>        Python module path for gvapython (e.g., /home/dlstreamer/add_data.py)
  -q <mqtt>          MQTT broker address (default: localhost:1883)
  -h                 Show this help message

Examples:
  Decode only:
    $0 -v video.h265 -n 4 -d GPU.0 -i 120

  Full AI pipeline with 8 streams in 2 processes (4 streams per process):
    $0 -v video.h265 -m FP16/yolo11n.xml -n 8 -P 2 -d GPU.0 -b 32 -i 120 -a

  With MQTT publishing:
    $0 -v video.h265 -m FP16/yolo11n.xml -n 4 -a -p /home/dlstreamer/add_data.py -q localhost:1883

EOF
    exit 0
}

# Parse arguments
GPU_CARD=""
BATCH_SIZE=1
while getopts "v:m:n:P:d:g:i:t:b:p:q:ah" opt; do
    case $opt in
        v) VIDEO_FILE="$OPTARG" ;;
        m) MODEL_PATH="$OPTARG" ;;
        n) NUM_STREAMS="$OPTARG" ;;
        P) NUM_PROCESSES="$OPTARG" ;;
        d) DEVICE="$OPTARG" ;;
        g) GPU_CARD="$OPTARG" ;;
        i) DURATION="$OPTARG" ;;
        t) TARGET_FPS="$OPTARG" ;;
        b) BATCH_SIZE="$OPTARG" ;;
        a) ENABLE_AI=true ;;
        p) PYTHON_MODULE="$OPTARG" ;;
        q) MQTT_ADDRESS="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Results directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="./benchmark_results_${NUM_STREAMS}streams_${NUM_PROCESSES}proc_bs${BATCH_SIZE}_${TIMESTAMP}"
mkdir -p "${RESULTS_DIR}"

LOG_FILE="${RESULTS_DIR}/benchmark.log"
SUMMARY_FILE="${RESULTS_DIR}/summary.txt"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Pipeline Benchmark${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Timestamp: ${TIMESTAMP}"
echo "Device: ${DEVICE}"
echo "Streams: ${NUM_STREAMS}"
echo "Processes: ${NUM_PROCESSES}"
echo "Duration: ${DURATION}s"
echo "Batch Size: ${BATCH_SIZE}"
echo "Video: ${VIDEO_FILE}"
echo "AI Enabled: ${ENABLE_AI}"
if [[ "${ENABLE_AI}" == true ]]; then
    echo "Model: ${MODEL_PATH}"
    if [[ -n "${PYTHON_MODULE}" ]]; then
        echo "Python Module: ${PYTHON_MODULE}"
        echo "MQTT: ${MQTT_ADDRESS}"
    fi
fi
echo "Results: ${RESULTS_DIR}"
echo ""

# Detect GPU card and render device
if [[ -z "${GPU_CARD}" ]]; then
    # Auto-detect based on device parameter
    if [[ "${DEVICE}" == "GPU.0" ]]; then
        CARD_DEV="/dev/dri/card0"
        RENDER_DEV="/dev/dri/renderD128"
    elif [[ "${DEVICE}" == "GPU.1" ]]; then
        CARD_DEV="/dev/dri/card1"
        RENDER_DEV="/dev/dri/renderD129"
    else
        CARD_DEV="/dev/dri/card0"
        RENDER_DEV="/dev/dri/renderD128"
    fi
else
    CARD_DEV="/dev/dri/${GPU_CARD}"
    # Calculate render device based on card number
    CARD_NUM="${GPU_CARD//[!0-9]/}"
    RENDER_NUM=$((128 + CARD_NUM))
    RENDER_DEV="/dev/dri/renderD${RENDER_NUM}"
fi

echo "GPU Card: ${CARD_DEV}"
echo "Render Device: ${RENDER_DEV}"
echo ""

# Cleanup function
cleanup() {
    if docker ps -q -f name="${CONTAINER_NAME}" 2>/dev/null; then
        echo -e "${YELLOW}[INFO]${NC} Stopping container..."
        docker stop -t 2 "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    fi
    if docker ps -aq -f name="${CONTAINER_NAME}" 2>/dev/null; then
        docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT INT TERM

# Start container
echo -e "${YELLOW}[INFO]${NC} Creating container: ${CONTAINER_NAME}"
docker run -d \
    --name "${CONTAINER_NAME}" \
    --device="${CARD_DEV}" \
    --device="${RENDER_DEV}" \
    --net=host \
    -v "${MOUNT_DIR}":/home/dlstreamer \
    -e PYTHONPATH="/opt/intel/dlstreamer/python" \
    -u root \
    "${IMAGE}" tail -f /dev/null >/dev/null

echo -e "${YELLOW}[INFO]${NC} Container created successfully"
echo ""

# Build GStreamer pipeline
# Choose between decode-only or full AI pipeline
if [[ "${ENABLE_AI}" == true ]]; then
    # Full AI pipeline with detection, tracking, and metadata processing
    AI_PIPELINE="gvadetect model=${MODEL_PATH} device=${DEVICE} pre-process-backend=vaapi-surface-sharing model-instance-id=inf0 batch-size=${BATCH_SIZE} ! gvatrack tracking-type=zero-term-imageless ! gvametaconvert add-empty-results=true json-indent=-1 timestamp-utc=true timestamp-microseconds=true"
    
    # Add optional Python processing and MQTT publishing
    if [[ -n "${PYTHON_MODULE}" ]]; then
        AI_PIPELINE="${AI_PIPELINE} ! gvapython module=${PYTHON_MODULE} ! queue ! gvametapublish method=mqtt address=${MQTT_ADDRESS} topic=dlstreamer async-handling=true"
    fi
    
    PIPELINE="multifilesrc location=${VIDEO_FILE} loop=true ! h265parse ! vah265dec ! vapostproc ! \"video/x-raw(memory:VAMemory)\" ! ${AI_PIPELINE} ! gvafpscounter starting-frame=100 ! fakesink sync=false async=false"
else
    # Decode-only pipeline for pure throughput testing
    PIPELINE="multifilesrc location=${VIDEO_FILE} loop=true ! h265parse ! vah265dec ! vapostproc ! \"video/x-raw(memory:VAMemory)\" ! queue ! gvafpscounter starting-frame=100 ! fakesink sync=false async=false"
fi

# Build complete command with multiple streams
# Calculate streams per process
STREAMS_PER_PROCESS=$(( (NUM_STREAMS + NUM_PROCESSES - 1) / NUM_PROCESSES ))

# Write pipeline information to log file
{
    echo "=========================================="
    echo "Pipeline Configuration"
    echo "=========================================="
    echo "Total Streams: ${NUM_STREAMS}"
    echo "Number of Processes: ${NUM_PROCESSES}"
    echo "Streams per Process: ~${STREAMS_PER_PROCESS}"
    echo ""
    echo "Single Stream Pipeline:"
    echo "${PIPELINE}"
    echo ""
    echo "=========================================="
    echo "Pipeline Output"
    echo "=========================================="
    echo ""
} > "${LOG_FILE}"

# Run benchmark in container with multiple processes
echo -e "${YELLOW}[INFO]${NC} Starting ${NUM_PROCESSES} process(es) with total ${NUM_STREAMS} streams (${DURATION}s)..."

PROCESS_PIDS=()
PROCESS_LOGS=()

for proc_id in $(seq 1 "${NUM_PROCESSES}"); do
    # Calculate streams for this process
    START_STREAM=$(( (proc_id - 1) * STREAMS_PER_PROCESS + 1 ))
    END_STREAM=$(( proc_id * STREAMS_PER_PROCESS ))
    if [[ ${END_STREAM} -gt ${NUM_STREAMS} ]]; then
        END_STREAM=${NUM_STREAMS}
    fi
    STREAMS_THIS_PROCESS=$(( END_STREAM - START_STREAM + 1 ))
    
    if [[ ${STREAMS_THIS_PROCESS} -le 0 ]]; then
        continue
    fi
    
    # Build pipeline for this process
    PROC_PIPELINE=""
    for i in $(seq 1 "${STREAMS_THIS_PROCESS}"); do
        PROC_PIPELINE="${PROC_PIPELINE} ${PIPELINE}"
    done
    
    # Create process-specific log file
    PROC_LOG="${RESULTS_DIR}/process_${proc_id}.log"
    PROCESS_LOGS+=("${PROC_LOG}")
    
    echo "  - Process ${proc_id}: ${STREAMS_THIS_PROCESS} streams (total: ${START_STREAM}-${END_STREAM})"
    
    # Start process in background
    (
        timeout --preserve-status "${DURATION}s" \
            docker exec "${CONTAINER_NAME}" bash -c "gst-launch-1.0 ${PROC_PIPELINE}" \
            2>&1 | grep --line-buffered -v "longjmp causes uninitialized stack frame"
    ) > "${PROC_LOG}" 2>&1 &
    
    PROCESS_PIDS+=($!)
    sleep 0.5
done

echo -e "${YELLOW}[INFO]${NC} Waiting for all processes to complete..."

# Wait for all processes to complete
for pid in "${PROCESS_PIDS[@]}"; do
    wait "${pid}" 2>/dev/null || true
done

# Merge all process logs
echo "" >> "${LOG_FILE}"
for i in "${!PROCESS_LOGS[@]}"; do
    proc_id=$((i + 1))
    echo "=========================================" >> "${LOG_FILE}"
    echo "Process ${proc_id} Output" >> "${LOG_FILE}"
    echo "=========================================" >> "${LOG_FILE}"
    cat "${PROCESS_LOGS[$i]}" >> "${LOG_FILE}"
    echo "" >> "${LOG_FILE}"
done

echo ""
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}=            Summary                  =${NC}"
echo -e "${GREEN}========================================${NC}"

# Parse results
if [[ -f "${LOG_FILE}" ]]; then
    # For multi-process setup, aggregate FPS from all process logs
    if [[ ${NUM_PROCESSES} -gt 1 ]]; then
        echo -e "${YELLOW}[INFO]${NC} Aggregating results from ${NUM_PROCESSES} processes..."
        
        TOTAL_THROUGHPUT=0
        PROCESS_COUNT=0
        
        for i in "${!PROCESS_LOGS[@]}"; do
            proc_id=$((i + 1))
            PROC_LOG="${PROCESS_LOGS[$i]}"
            
            if [[ -f "${PROC_LOG}" ]]; then
                # Get the last average FPS from this process
                PROC_FPS=$(grep 'FpsCounter' "${PROC_LOG}" | grep 'average' | tail -n1 | sed 's/.*total=//' | cut -d' ' -f1)
                
                if [[ -n "${PROC_FPS}" && "${PROC_FPS}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
                    TOTAL_THROUGHPUT=$(LC_ALL=C awk -v t="${TOTAL_THROUGHPUT}" -v p="${PROC_FPS}" \
                        'BEGIN { printf("%.2f", t + p) }')
                    PROCESS_COUNT=$((PROCESS_COUNT + 1))
                    echo "  - Process ${proc_id}: ${PROC_FPS} fps"
                fi
            fi
        done
        
        if [[ ${PROCESS_COUNT} -eq 0 ]]; then
            echo -e "${RED}[ERROR]${NC} No valid FPS data found in process logs"
            exit 1
        fi
        
        THROUGHPUT="${TOTAL_THROUGHPUT}"
        echo "  - Total aggregated: ${THROUGHPUT} fps from ${PROCESS_COUNT} processes"
    else
        # Single process - use original logic
            THROUGHPUT=$(grep 'FpsCounter' "${LOG_FILE}" | grep 'average' | tail -n1 | sed 's/.*total=//' | cut -d' ' -f1)
    
    fi
    
    if [[ -n "${THROUGHPUT}" && "${THROUGHPUT}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        THROUGHPUT_PER_STREAM=$(LC_ALL=C awk -v t="${THROUGHPUT}" -v n="${NUM_STREAMS}" \
            'BEGIN { printf("%.2f", t / n) }')
        
        THEORETICAL_STREAMS=$(LC_ALL=C awk -v t="${THROUGHPUT}" -v f="${TARGET_FPS}" \
            'BEGIN { printf("%d", int(t / f)) }')
        
        echo -e "${GREEN}[ Info ]${NC} Average Total Throughput: ${THROUGHPUT} fps"
        echo -e "${GREEN}[ Info ]${NC} Throughput per Stream (${NUM_STREAMS}): ${THROUGHPUT_PER_STREAM} fps/stream"
        echo -e "${GREEN}[ Info ]${NC} Theoretical Stream Density (@${TARGET_FPS}): ${THEORETICAL_STREAMS}"
        
        # Save summary
        {
            echo "======================================"
            echo "Benchmark Summary"
            echo "======================================"
            echo "Timestamp: ${TIMESTAMP}"
            echo "Device: ${DEVICE}"
            echo "GPU Card: ${CARD_DEV}"
            echo "Number of Streams: ${NUM_STREAMS}"
            echo "Number of Processes: ${NUM_PROCESSES}"
            echo "Duration: ${DURATION}s"
            echo "Batch Size: ${BATCH_SIZE}"
            echo "Target FPS: ${TARGET_FPS}"
            echo "Video File: ${VIDEO_FILE}"
            echo "AI Enabled: ${ENABLE_AI}"
            if [[ "${ENABLE_AI}" == true ]]; then
                echo "Model Path: ${MODEL_PATH}"
                if [[ -n "${PYTHON_MODULE}" ]]; then
                    echo "Python Module: ${PYTHON_MODULE}"
                    echo "MQTT Address: ${MQTT_ADDRESS}"
                fi
            fi
            echo ""
            echo "Results:"
            echo "--------------------------------------"
            echo "Average Total Throughput: ${THROUGHPUT} fps"
            echo "Throughput per Stream: ${THROUGHPUT_PER_STREAM} fps/stream"
            echo "Theoretical Stream Density: ${THEORETICAL_STREAMS}"
            echo ""
            echo "Pipeline:"
            echo "${PIPELINE}"
            echo ""
        } > "${SUMMARY_FILE}"
        
        echo ""
        echo -e "${GREEN}[SUCCESS]${NC} Results saved to: ${RESULTS_DIR}"
        
    else
        echo -e "${RED}[ERROR]${NC} Could not parse throughput from log"
        exit 1
    fi
else
    echo -e "${RED}[ERROR]${NC} Log file not found"
    exit 1
fi

echo ""
