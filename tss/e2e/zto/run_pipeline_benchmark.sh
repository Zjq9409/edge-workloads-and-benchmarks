#!/bin/bash

# Enhanced Pipeline Benchmark Script
# Run GStreamer pipeline in container and collect statistics

set -e

# 默认单进程（与原来一样）
#./run_pipeline_benchmark.sh -n 8 -d GPU.0 -i 120


# 完整 Pipeline - FP32 模型（32路流）
#./run_pipeline_benchmark.sh -n 32 -P 4 -d GPU.0 -b 32 -i 120

# 完整 Pipeline - INT8 模型（48路流，更高性能）
#./run_pipeline_benchmark.sh -n 48 -P 6 -d GPU.0 -b 32 -i 120 -int8

# Auto-tune 找最大流数
#./run_pipeline_benchmark.sh -n 40 -d GPU.0 -b 32 -T

# Configuration
# Auto-detect Ubuntu version and select appropriate Docker image
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${VERSION_ID}" == "22.04" ]]; then
        IMAGE="intel/dlstreamer:2025.2.0-ubuntu22"
    elif [[ "${VERSION_ID}" == "24.04" ]]; then
        IMAGE="intel/dlstreamer:2025.2.0-ubuntu24"
    else
        echo -e "\033[0;31m[ERROR]\033[0m Unsupported Ubuntu version: ${VERSION_ID}"
        echo "Supported versions: 22.04, 24.04"
        exit 1
    fi
else
    echo -e "\033[0;31m[ERROR]\033[0m Cannot detect OS version (/etc/os-release not found)"
    exit 1
fi
MOUNT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CONTAINER_NAME="benchmark_$$"
DURATION=120
TARGET_FPS=25
NUM_STREAMS=1
NUM_PROCESSES=1
PROCESS_SWEEP=""
DEVICE="GPU.0"
VIDEO_FILE="/home/dlstreamer/work/media-downloader/media/hevc/apple_720p25_loop30.h265"
MODEL_PATH_INT8="/home/dlstreamer/work/model-conversion/models/yolo11n/yolo11n_int8.xml"
MODEL_PATH_FP32="/home/dlstreamer/work/model-conversion/models/yolo11n/yolo11n_fp32.xml"
MODEL_PATH="${MODEL_PATH_FP32}"  # Default to FP32
USE_INT8=false
ENABLE_AI=true  # Default: run full AI pipeline
MQTT_ADDRESS="localhost:1883"
PYTHON_MODULE="/home/dlstreamer/add_data.py"  # Default: enable metadata processing and MQTT
AUTO_TUNE=false
TUNE_THRESHOLD=25.0
TUNE_SHORT_DURATION=20

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check and stop any existing benchmark containers
cleanup_existing_benchmark_containers() {
    echo -e "${YELLOW}[INFO]${NC} Checking for existing benchmark containers..."
    
    # Find all benchmark_* containers (both running and stopped)
    local benchmark_containers=$(docker ps -a --filter "name=^benchmark_" --format "{{.Names}}" 2>/dev/null)
    
    if [[ -z "${benchmark_containers}" ]]; then
        echo -e "${GREEN}[INFO]${NC} No existing benchmark containers found"
        return 0
    fi
    
    # Count containers
    local count=$(echo "${benchmark_containers}" | wc -l)
    echo -e "${YELLOW}[WARNING]${NC} Found ${count} existing benchmark container(s)"
    
    # Show container details
    echo -e "${YELLOW}[INFO]${NC} Container details:"
    docker ps -a --filter "name=^benchmark_" --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}" | head -6
    
    # Stop and remove containers
    echo -e "${YELLOW}[INFO]${NC} Stopping and removing benchmark containers..."
    for container in ${benchmark_containers}; do
        echo -e "${YELLOW}[INFO]${NC}   Stopping ${container}..."
        if docker stop -t 2 "${container}" >/dev/null 2>&1; then
            echo -e "${GREEN}[INFO]${NC}     Stopped ${container}"
        fi
        if docker rm "${container}" >/dev/null 2>&1; then
            echo -e "${GREEN}[INFO]${NC}     Removed ${container}"
        fi
    done
    
    # Verify cleanup
    local remaining=$(docker ps -a --filter "name=^benchmark_" --format "{{.Names}}" 2>/dev/null | wc -l)
    
    if [[ ${remaining} -eq 0 ]]; then
        echo -e "${GREEN}[INFO]${NC} All benchmark containers cleaned up successfully"
        return 0
    else
        echo -e "${YELLOW}[WARNING]${NC} ${remaining} container(s) still remaining"
        return 1
    fi
}

# Check and start MQTT broker if needed
ensure_mqtt_broker() {
    local mqtt_container="dlstreamer_mqtt"
    
    # Check if MQTT container is running
    if docker ps --format '{{.Names}}' | grep -q "^${mqtt_container}$"; then
        echo -e "${GREEN}[INFO]${NC} MQTT broker is already running"
        return 0
    fi
    
    # Check if container exists but is stopped
    if docker ps -a --format '{{.Names}}' | grep -q "^${mqtt_container}$"; then
        echo -e "${YELLOW}[INFO]${NC} Starting existing MQTT broker container..."
        docker start "${mqtt_container}" >/dev/null 2>&1
    else
        echo -e "${YELLOW}[INFO]${NC} Starting MQTT broker container..."
        docker run -d --rm \
            --name "${mqtt_container}" \
            -p 1883:1883 \
            -p 9001:9001 \
            eclipse-mosquitto:1.6 >/dev/null 2>&1
    fi
    
    # Wait for MQTT to be ready
    sleep 2
    
    if docker ps --format '{{.Names}}' | grep -q "^${mqtt_container}$"; then
        echo -e "${GREEN}[INFO]${NC} MQTT broker started successfully"
        return 0
    else
        echo -e "${RED}[WARNING]${NC} Failed to start MQTT broker"
        return 1
    fi
}

# Usage
usage() {
    cat << EOF
AI Pipeline Benchmark - Full inference pipeline with detection, tracking, and metadata

Usage: $0 [OPTIONS]

Common options:
  -n <num_streams>   Number of AI streams (default: 1)
  -P <num_processes> Number of processes (default: 1)
  -P-sweep <list>    Test multiple process counts (e.g., "1,2,4,8")
  -d <device>        GPU device: GPU.0, GPU.1 (default: GPU.0)
  -b <batch_size>    Inference batch size (default: 1)
  -i <duration>      Test duration in seconds (default: 120)
  -a                 Enable AI inference (required for AI pipeline)
  -int8              Use INT8 model (default: FP32)
  -T                 Enable auto-tune mode
  -h                 Show this help message

Examples:
  ./run_pipeline_benchmark.sh -n 32 -P 4 -d GPU.0 -b 32 -a -i 120
  ./run_pipeline_benchmark.sh -n 48 -P 6 -d GPU.0 -b 32 -a -int8 -i 120
  ./run_pipeline_benchmark.sh -n 40 -d GPU.0 -b 32 -a -T
  ./run_pipeline_benchmark.sh -n 32 -P-sweep "1,2,4,8" -d GPU.0 -b 32 -a -i 120

For detailed documentation, see: README.md

EOF
    exit 0
}

# Parse arguments
GPU_CARD=""
BATCH_SIZE=1
MODEL_OVERRIDE=""

# Process all arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -int8)
            USE_INT8=true
            shift
            ;;
        -v)
            VIDEO_FILE="$2"
            shift 2
            ;;
        -m)
            MODEL_OVERRIDE="$2"
            shift 2
            ;;
        -n)
            NUM_STREAMS="$2"
            shift 2
            ;;
        -P)
            NUM_PROCESSES="$2"
            shift 2
            ;;
        -P-sweep)
            PROCESS_SWEEP="$2"
            shift 2
            ;;
        -d)
            DEVICE="$2"
            shift 2
            ;;
        -g)
            GPU_CARD="$2"
            shift 2
            ;;
        -i)
            DURATION="$2"
            shift 2
            ;;
        -t)
            TARGET_FPS="$2"
            shift 2
            ;;
        -b)
            BATCH_SIZE="$2"
            shift 2
            ;;
        -p)
            PYTHON_MODULE="$2"
            shift 2
            ;;
        -q)
            MQTT_ADDRESS="$2"
            shift 2
            ;;
        -s)
            TUNE_THRESHOLD="$2"
            shift 2
            ;;
        -a)
            ENABLE_AI=true
            shift
            ;;
        -T)
            AUTO_TUNE=true
            shift
            ;;
        -h)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Apply INT8 model selection if flag is set
if [[ "${USE_INT8}" == true ]]; then
    MODEL_PATH="${MODEL_PATH_INT8}"
fi

# Allow manual model override
if [[ -n "${MODEL_OVERRIDE}" ]]; then
    MODEL_PATH="${MODEL_OVERRIDE}"
fi

# Process sweep mode - test multiple process counts
if [[ -n "${PROCESS_SWEEP}" ]]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Process Sweep Mode${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "Testing process counts: ${PROCESS_SWEEP}"
    echo "Streams: ${NUM_STREAMS}"
    echo "Device: ${DEVICE}"
    echo "Batch Size: ${BATCH_SIZE}"
    echo "Duration: ${DURATION}s"
    echo "Model Precision: $([ "${USE_INT8}" = true ] && echo "INT8" || echo "FP32")"
    echo ""
    
    # Parse process counts
    IFS=',' read -ra PROCESS_COUNTS <<< "${PROCESS_SWEEP}"
    
    # Create sweep results directory
    SWEEP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    SWEEP_PRECISION=$([ "${USE_INT8}" = true ] && echo "int8" || echo "fp32")
    SWEEP_DIR="./process_sweep_${NUM_STREAMS}streams_bs${BATCH_SIZE}_${SWEEP_PRECISION}_${SWEEP_TIMESTAMP}"
    mkdir -p "${SWEEP_DIR}"
    
    SWEEP_SUMMARY="${SWEEP_DIR}/sweep_summary.txt"
    
    # Write sweep header
    {
        echo "======================================"
        echo "Process Sweep Test Summary"
        echo "======================================"
        echo "Timestamp: ${SWEEP_TIMESTAMP}"
        echo "Total Streams: ${NUM_STREAMS}"
        echo "Device: ${DEVICE}"
        echo "Batch Size: ${BATCH_SIZE}"
        echo "Duration: ${DURATION}s per test"
        echo "Model Precision: ${SWEEP_PRECISION}"
        echo "Process Counts Tested: ${PROCESS_SWEEP}"
        echo ""
        echo "======================================"
        echo "Individual Test Results"
        echo "======================================"
        echo ""
    } > "${SWEEP_SUMMARY}"
    
    declare -a SWEEP_RESULTS
    
    # Run tests for each process count
    for proc_count in "${PROCESS_COUNTS[@]}"; do
        # Trim whitespace
        proc_count=$(echo "${proc_count}" | xargs)
        
        if [[ ! "${proc_count}" =~ ^[0-9]+$ ]] || [[ ${proc_count} -lt 1 ]]; then
            echo -e "${RED}[ERROR]${NC} Invalid process count: ${proc_count}"
            continue
        fi
        
        echo -e "${YELLOW}[SWEEP]${NC} Testing with ${proc_count} process(es)..."
        echo ""
        
        # Build command arguments (exclude -P-sweep to avoid recursion)
        TEST_ARGS="-n ${NUM_STREAMS} -P ${proc_count} -d ${DEVICE} -b ${BATCH_SIZE} -i ${DURATION}"
        [[ "${ENABLE_AI}" == true ]] && TEST_ARGS="${TEST_ARGS} -a"
        [[ "${USE_INT8}" == true ]] && TEST_ARGS="${TEST_ARGS} -int8"
        [[ -n "${VIDEO_FILE}" ]] && TEST_ARGS="${TEST_ARGS} -v ${VIDEO_FILE}"
        [[ -n "${MODEL_OVERRIDE}" ]] && TEST_ARGS="${TEST_ARGS} -m ${MODEL_OVERRIDE}"
        [[ -n "${PYTHON_MODULE}" ]] && TEST_ARGS="${TEST_ARGS} -p ${PYTHON_MODULE}"
        [[ -n "${MQTT_ADDRESS}" ]] && TEST_ARGS="${TEST_ARGS} -q ${MQTT_ADDRESS}"
        
        # Run the test (call script recursively without -P-sweep)
        if bash "$0" ${TEST_ARGS} 2>&1 | tee "${SWEEP_DIR}/test_${proc_count}proc.log"; then
            # Extract throughput per stream from the last line of output
            RESULT_FPS=$(tail -n 1 "${SWEEP_DIR}/test_${proc_count}proc.log")
            
            if [[ "${RESULT_FPS}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
                TOTAL_FPS=$(LC_ALL=C awk -v fps="${RESULT_FPS}" -v streams="${NUM_STREAMS}" \
                    'BEGIN { printf("%.2f", fps * streams) }')
                
                SWEEP_RESULTS+=("${proc_count}:${RESULT_FPS}:${TOTAL_FPS}")
                
                echo ""
                echo -e "${GREEN}[SWEEP]${NC} Result: ${proc_count} proc -> ${RESULT_FPS} fps/stream (Total: ${TOTAL_FPS} fps)"
                
                # Append to summary
                {
                    echo "Process Count: ${proc_count}"
                    echo "  FPS per Stream: ${RESULT_FPS}"
                    echo "  Total Throughput: ${TOTAL_FPS} fps"
                    echo ""
                } >> "${SWEEP_SUMMARY}"
            else
                echo -e "${RED}[SWEEP]${NC} Failed to get valid result for ${proc_count} process(es)"
                {
                    echo "Process Count: ${proc_count}"
                    echo "  Status: FAILED"
                    echo ""
                } >> "${SWEEP_SUMMARY}"
            fi
        else
            echo -e "${RED}[SWEEP]${NC} Test failed for ${proc_count} process(es)"
            {
                echo "Process Count: ${proc_count}"
                echo "  Status: ERROR"
                echo ""
            } >> "${SWEEP_SUMMARY}"
        fi
        
        echo ""
        echo -e "${YELLOW}[SWEEP]${NC} Waiting 5 seconds before next test..."
        sleep 5
    done
    
    # Write comparison summary
    {
        echo "======================================"
        echo "Comparison Summary"
        echo "======================================"
        printf "%-12s %-18s %-18s\n" "Processes" "FPS/Stream" "Total FPS"
        echo "--------------------------------------"
    } >> "${SWEEP_SUMMARY}"
    
    # Find best result
    BEST_FPS=0
    BEST_PROC=0
    
    for result in "${SWEEP_RESULTS[@]}"; do
        IFS=':' read -r proc fps total <<< "${result}"
        printf "%-12s %-18s %-18s\n" "${proc}" "${fps}" "${total}" >> "${SWEEP_SUMMARY}"
        
        # Check if this is the best
        IS_BEST=$(LC_ALL=C awk -v total="${total}" -v best="${BEST_FPS}" \
            'BEGIN { print (total > best) ? 1 : 0 }')
        if [[ ${IS_BEST} -eq 1 ]]; then
            BEST_FPS="${total}"
            BEST_PROC="${proc}"
        fi
    done
    
    {
        echo ""
        echo "Best Configuration:"
        echo "  Process Count: ${BEST_PROC}"
        echo "  Total Throughput: ${BEST_FPS} fps"
        echo ""
        echo "Results saved to: ${SWEEP_DIR}"
        echo ""
    } >> "${SWEEP_SUMMARY}"
    
    # Display summary
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Process Sweep Complete${NC}"
    echo -e "${GREEN}========================================${NC}"
    cat "${SWEEP_SUMMARY}"
    
    exit 0
fi

# Auto-tune mode function
run_auto_tune() {
    local current_streams=$NUM_STREAMS
    local max_streams=0
    local max_streams_fps=0
    local step_size=10
    local test_duration=$TUNE_SHORT_DURATION
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Auto-Tune Mode: Finding Maximum Streams${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "Starting streams: ${current_streams}"
    echo "FPS threshold: ${TUNE_THRESHOLD}"
    echo "Test duration: ${test_duration}s per iteration"
    echo "Device: ${DEVICE}"
    echo ""
    
    while true; do
        # Calculate processes for current streams (about 8 streams per process)
        local processes=$(( (current_streams + 7) / 8 ))
        
        echo -e "${YELLOW}[TUNE]${NC} Testing ${current_streams} streams with ${processes} processes..."
        
        # Run benchmark with short duration
        local result_fps=$(DURATION=$test_duration NUM_STREAMS=$current_streams NUM_PROCESSES=$processes \
            bash "$0" -v "$VIDEO_FILE" -m "$MODEL_PATH" -n $current_streams -P $processes \
            -d "$DEVICE" -b "$BATCH_SIZE" -i $test_duration -t "$TARGET_FPS" \
            $([ "$ENABLE_AI" = true ] && echo "-a") \
            $([ -n "$PYTHON_MODULE" ] && echo "-p $PYTHON_MODULE") \
            $([ -n "$MQTT_ADDRESS" ] && echo "-q $MQTT_ADDRESS") \
            2>/dev/null | tail -1)
        
        # Check if result is valid
        if [[ ! "$result_fps" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            echo -e "${RED}[TUNE]${NC} Failed to get valid result, stopping"
            break
        fi
        
        echo -e "${YELLOW}[TUNE]${NC} Result: ${result_fps} fps/stream (threshold: ${TUNE_THRESHOLD})"
        
        # Check if passed threshold
        local passed=$(LC_ALL=C awk -v fps="$result_fps" -v threshold="$TUNE_THRESHOLD" \
            'BEGIN { print (fps >= threshold) ? 1 : 0 }')
        
        if [[ $passed -eq 1 ]]; then
            echo -e "${GREEN}[TUNE]${NC} + Passed threshold"
            max_streams=$current_streams
            max_streams_fps=$result_fps
            current_streams=$((current_streams + step_size))
        else
            echo -e "${RED}[TUNE]${NC} X Failed threshold"
            
            if [[ $step_size -gt 2 ]]; then
                step_size=2
                current_streams=$((max_streams + step_size))
                echo -e "${YELLOW}[TUNE]${NC} Reducing step size to ${step_size}"
            else
                break
            fi
        fi
        
        # Safety limit
        if [[ $current_streams -gt 200 ]]; then
            echo -e "${YELLOW}[TUNE]${NC} Reached safety limit of 200 streams"
            break
        fi
        
        echo ""
    done
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Auto-Tune Results${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "Maximum Streams: ${max_streams}"
    echo "FPS per Stream: ${max_streams_fps}"
    echo "Total Throughput: $(LC_ALL=C awk -v s="$max_streams" -v f="$max_streams_fps" 'BEGIN { printf("%.2f", s * f) }') fps"
    echo "FPS Threshold: ${TUNE_THRESHOLD}"
    echo ""
    echo "To verify with full duration test:"
    echo "  $0 -v \"$VIDEO_FILE\" -n ${max_streams} -P $(( (max_streams + 7) / 8 )) -d \"$DEVICE\" -b ${BATCH_SIZE} -i 120 $([ "$ENABLE_AI" = true ] && echo "-a -m \"$MODEL_PATH\"")"
    echo ""
    
    exit 0
}

# Check if auto-tune mode is enabled
if [[ "${AUTO_TUNE}" == true ]]; then
    run_auto_tune
fi

# Results directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
if [[ "${USE_INT8}" == true ]]; then
    PRECISION="int8"
else
    PRECISION="fp32"
fi
RESULTS_DIR="./benchmark_results_${NUM_STREAMS}streams_${NUM_PROCESSES}proc_bs${BATCH_SIZE}_${PRECISION}_${TIMESTAMP}"
mkdir -p "${RESULTS_DIR}"

LOG_FILE="${RESULTS_DIR}/benchmark.log"
SUMMARY_FILE="${RESULTS_DIR}/summary.txt"
MONITOR_CSV="${RESULTS_DIR}/gpu_monitor.csv"

# GPU monitor script path
GPU_MONITOR_SCRIPT="../../../utils/gpu_monitor.sh"

# Clean up any existing benchmark containers before starting
cleanup_existing_benchmark_containers
echo ""

# Ensure MQTT broker is running if AI is enabled
if [[ "${ENABLE_AI}" == true ]]; then
    ensure_mqtt_broker
    echo ""
fi

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
    echo "Python Module: ${PYTHON_MODULE}"
    echo "MQTT: ${MQTT_ADDRESS}"
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
    # Stop GPU monitoring if running
    if [[ -n "${MONITOR_PID}" ]] && kill -0 "${MONITOR_PID}" 2>/dev/null; then
        echo -e "${YELLOW}[INFO]${NC} Stopping GPU monitor..."
        kill "${MONITOR_PID}" 2>/dev/null || true
        wait "${MONITOR_PID}" 2>/dev/null || true
    fi
    
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
    -v "${MOUNT_DIR}":/home/dlstreamer/work \
    -e PYTHONPATH="/opt/intel/dlstreamer/python" \
    -u root \
    "${IMAGE}" tail -f /dev/null >/dev/null

echo -e "${YELLOW}[INFO]${NC} Container created successfully"

# Copy add_data.py if it exists and AI is enabled
if [[ "${ENABLE_AI}" == true ]]; then
    # Check if Python module is already accessible via mounted volume
    if [[ "${PYTHON_MODULE}" == /home/dlstreamer/work/* ]]; then
        echo -e "${GREEN}[INFO]${NC} Python module accessible via mounted volume: ${PYTHON_MODULE}"
    else
        # Need to copy the file to container
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        LOCAL_PYTHON_FILE="${SCRIPT_DIR}/add_data.py"
        
        if [[ -f "${LOCAL_PYTHON_FILE}" ]]; then
            echo -e "${YELLOW}[INFO]${NC} Copying Python module to container..."
            docker cp "${LOCAL_PYTHON_FILE}" "${CONTAINER_NAME}:${PYTHON_MODULE}" >/dev/null 2>&1
            
            if [[ $? -eq 0 ]]; then
                echo -e "${GREEN}[INFO]${NC} Python module copied to ${PYTHON_MODULE}"
            else
                echo -e "${RED}[ERROR]${NC} Failed to copy Python module"
                echo -e "${RED}[ERROR]${NC} Python module is required for AI pipeline"
                exit 1
            fi
        else
            echo -e "${RED}[ERROR]${NC} add_data.py not found at ${LOCAL_PYTHON_FILE}"
            echo -e "${RED}[ERROR]${NC} Python module is required for AI pipeline"
            exit 1
        fi
    fi
fi

echo ""

# Request sudo access upfront for GPU monitoring
echo -e "${YELLOW}[INFO]${NC} GPU monitoring requires sudo access. Please enter your password:"
sudo -v || {
    echo -e "${RED}[ERROR]${NC} Failed to obtain sudo access"
    exit 1
}

# Start GPU monitoring
MONITOR_PID=""
if [[ -f "${GPU_MONITOR_SCRIPT}" ]]; then
    # Extract device number from DEVICE (e.g., GPU.0 -> 0)
    DEVICE_NUM="${DEVICE##*.}"
    
    # Determine model info for monitoring
    if [[ "${ENABLE_AI}" == true ]]; then
        if [[ "${USE_INT8}" == true ]]; then
            MODEL_INFO="yolo11n_int8"
        else
            MODEL_INFO="yolo11n_fp32"
        fi
    else
        MODEL_INFO="decode_only"
    fi
    
    echo -e "${YELLOW}[INFO]${NC} Starting GPU monitor for device ${DEVICE_NUM}..."
    echo -e "${YELLOW}[INFO]${NC} Please enter sudo password if prompted..."
    bash "${GPU_MONITOR_SCRIPT}" "${MONITOR_CSV}" "${DEVICE_NUM}" 1 "${MODEL_INFO}" "${BATCH_SIZE}" "${RESULTS_DIR}" &
    MONITOR_PID=$!
    
    # Wait for monitor to start and collect first data point
    echo -e "${YELLOW}[INFO]${NC} Waiting for GPU monitor to initialize..."
    WAIT_COUNT=0
    MAX_WAIT=20
    
    while [[ ${WAIT_COUNT} -lt ${MAX_WAIT} ]]; do
        # Check if process is still running
        if ! kill -0 "${MONITOR_PID}" 2>/dev/null; then
            echo -e "${RED}[WARNING]${NC} GPU monitor process terminated unexpectedly"
            MONITOR_PID=""
            break
        fi
        
        # Check if CSV file has data (more than just header)
        if [[ -f "${MONITOR_CSV}" ]]; then
            LINE_COUNT=$(wc -l < "${MONITOR_CSV}" 2>/dev/null || echo "0")
            if [[ ${LINE_COUNT} -gt 1 ]]; then
                echo -e "${GREEN}[INFO]${NC} GPU monitor started successfully (PID: ${MONITOR_PID})"
                echo -e "${GREEN}[INFO]${NC} Monitor output: ${MONITOR_CSV}"
                echo -e "${GREEN}[INFO]${NC} First data point collected, proceeding with benchmark..."
                break
            fi
        fi
        
        sleep 1
        WAIT_COUNT=$((WAIT_COUNT + 1))
        
        # Show progress every 5 seconds
        if [[ $((WAIT_COUNT % 5)) -eq 0 ]]; then
            echo -e "${YELLOW}[INFO]${NC} Still waiting for GPU monitor... (${WAIT_COUNT}/${MAX_WAIT}s)"
        fi
    done
    
    # Final check
    if [[ ${WAIT_COUNT} -ge ${MAX_WAIT} ]]; then
        echo -e "${RED}[WARNING]${NC} GPU monitor initialization timeout, continuing without monitoring"
        if [[ -n "${MONITOR_PID}" ]] && kill -0 "${MONITOR_PID}" 2>/dev/null; then
            kill "${MONITOR_PID}" 2>/dev/null || true
        fi
        MONITOR_PID=""
    fi
else
    echo -e "${YELLOW}[WARNING]${NC} GPU monitor script not found: ${GPU_MONITOR_SCRIPT}"
fi

echo ""

# Build GStreamer pipeline
# Choose between decode-only or full AI pipeline
if [[ "${ENABLE_AI}" == true ]]; then
    # Full AI pipeline with detection, tracking, metadata processing, and MQTT publishing
    AI_PIPELINE="gvadetect model=${MODEL_PATH} device=${DEVICE} pre-process-backend=vaapi-surface-sharing model-instance-id=inf0 batch-size=${BATCH_SIZE} ! gvatrack tracking-type=zero-term-imageless ! gvametaconvert add-empty-results=true json-indent=-1 timestamp-utc=true timestamp-microseconds=true ! gvapython module=${PYTHON_MODULE} ! queue ! gvametapublish method=mqtt address=${MQTT_ADDRESS} topic=dlstreamer async-handling=true"
    
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

# Stop GPU monitoring (will auto-generate plots on exit)
if [[ -n "${MONITOR_PID}" ]] && kill -0 "${MONITOR_PID}" 2>/dev/null; then
    echo -e "${YELLOW}[INFO]${NC} Stopping GPU monitor..."
    kill "${MONITOR_PID}" 2>/dev/null || true
    wait "${MONITOR_PID}" 2>/dev/null || true
fi

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
        echo -e "${YELLOW}[INFO]${NC} Validating process execution..."
        
        # First pass: validate all processes ran for sufficient duration
        MIN_DURATION=$(LC_ALL=C awk -v d="${DURATION}" 'BEGIN { printf("%.0f", d * 0.9) }')
        FAILED_PROCESSES=()
        
        for i in "${!PROCESS_LOGS[@]}"; do
            proc_id=$((i + 1))
            PROC_LOG="${PROCESS_LOGS[$i]}"
            
            if [[ -f "${PROC_LOG}" ]]; then
                # Extract runtime from last FpsCounter line (average XXXsec)
                PROC_RUNTIME=$(grep 'FpsCounter' "${PROC_LOG}" | grep 'average' | tail -n1 | sed -n 's/.*average \([0-9.]*\)sec.*/\1/p')
                
                if [[ -z "${PROC_RUNTIME}" ]]; then
                    echo -e "${RED}  X Process ${proc_id}: No FPS data found${NC}"
                    FAILED_PROCESSES+=("${proc_id}")
                else
                    # Check if runtime meets minimum threshold
                    RUNTIME_OK=$(LC_ALL=C awk -v r="${PROC_RUNTIME}" -v m="${MIN_DURATION}" \
                        'BEGIN { print (r >= m) ? 1 : 0 }')
                    
                    if [[ ${RUNTIME_OK} -eq 0 ]]; then
                        echo -e "${RED}  X Process ${proc_id}: Terminated early (${PROC_RUNTIME}s / ${DURATION}s expected)${NC}"
                        FAILED_PROCESSES+=("${proc_id}")
                    else
                        echo -e "${GREEN}  + Process ${proc_id}: Completed (${PROC_RUNTIME}s)${NC}"
                    fi
                fi
            else
                echo -e "${RED}  X Process ${proc_id}: Log file not found${NC}"
                FAILED_PROCESSES+=("${proc_id}")
            fi
        done
        
        # If any process failed, report and exit
        if [[ ${#FAILED_PROCESSES[@]} -gt 0 ]]; then
            echo ""
            echo -e "${RED}[ERROR]${NC} Benchmark failed: ${#FAILED_PROCESSES[@]} process(es) terminated abnormally"
            echo -e "${RED}[ERROR]${NC} Failed processes: ${FAILED_PROCESSES[*]}"
            echo ""
            echo "Possible causes:"
            echo "  - System resource exhaustion (GPU/memory overload)"
            echo "  - Pipeline errors or crashes"
            echo "  - Container or Docker issues"
            echo ""
            echo "Suggestions:"
            echo "  - Reduce number of streams (-n)"
            echo "  - Reduce batch size (-b)"
            echo "  - Check process logs in: ${RESULTS_DIR}/"
            echo "  - Try running with fewer processes (-P)"
            echo ""
            exit 1
        fi
        
        echo ""
        echo -e "${YELLOW}[INFO]${NC} Aggregating results from ${NUM_PROCESSES} processes..."
        
        TOTAL_THROUGHPUT=0
        PROCESS_COUNT=0
        declare -a PROCESS_FPS_ARRAY
        declare -a PROCESS_LATENCY_ARRAY
        
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
                    
                    # Calculate per-process batch latency
                    PROC_BATCH_LATENCY=$(LC_ALL=C awk -v b="${BATCH_SIZE}" -v f="${PROC_FPS}" \
                        'BEGIN { printf("%.2f", (b / f) * 1000) }')
                    
                    PROCESS_FPS_ARRAY+=("${PROC_FPS}")
                    PROCESS_LATENCY_ARRAY+=("${PROC_BATCH_LATENCY}")
                    
                    echo "  - Process ${proc_id}: ${PROC_FPS} fps (Batch latency: ${PROC_BATCH_LATENCY} ms)"
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
        # Single process - use original logic with validation
        echo -e "${YELLOW}[INFO]${NC} Validating process execution..."
        
        # Extract runtime from last FpsCounter line
        PROC_RUNTIME=$(grep 'FpsCounter' "${LOG_FILE}" | grep 'average' | tail -n1 | sed -n 's/.*average \([0-9.]*\)sec.*/\1/p')
        MIN_DURATION=$(LC_ALL=C awk -v d="${DURATION}" 'BEGIN { printf("%.0f", d * 0.9) }')
        
        if [[ -z "${PROC_RUNTIME}" ]]; then
            echo -e "${RED}[ERROR]${NC} No FPS data found in log"
            exit 1
        fi
        
        RUNTIME_OK=$(LC_ALL=C awk -v r="${PROC_RUNTIME}" -v m="${MIN_DURATION}" \
            'BEGIN { print (r >= m) ? 1 : 0 }')
        
        if [[ ${RUNTIME_OK} -eq 0 ]]; then
            echo -e "${RED}[ERROR]${NC} Process terminated early (${PROC_RUNTIME}s / ${DURATION}s expected)"
            echo ""
            echo "Check log file for errors: ${LOG_FILE}"
            exit 1
        fi
        
        echo -e "${GREEN}  + Process completed (${PROC_RUNTIME}s)${NC}"
        echo ""
        
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
        
        # Calculate latency information for AI pipeline
        if [[ "${ENABLE_AI}" == true ]]; then
            echo ""
            echo -e "${YELLOW}[INFO]${NC} Calculating latency metrics..."
            
            # Decode latency estimate (H.265 720p hardware decode)
            DECODE_LATENCY="2-4"
            DECODE_AVG=3.0
            
            # Display per-process latency details
            if [[ ${NUM_PROCESSES} -gt 1 ]]; then
                echo ""
                echo -e "${GREEN}[ Info ]${NC} Per-Process Latency (Batch Size: ${BATCH_SIZE}):"
                for i in "${!PROCESS_LATENCY_ARRAY[@]}"; do
                    proc_id=$((i + 1))
                    PROC_FPS="${PROCESS_FPS_ARRAY[$i]}"
                    PROC_LATENCY="${PROCESS_LATENCY_ARRAY[$i]}"
                    
                    PROC_PER_FRAME=$(LC_ALL=C awk -v b="${BATCH_SIZE}" -v total="${PROC_LATENCY}" \
                        'BEGIN { printf "%.2f", total / b }')
                    
                    echo -e "${GREEN}[ Info ]${NC}   Process ${proc_id}:"
                    echo -e "${GREEN}[ Info ]${NC}     - Throughput: ${PROC_FPS} fps"
                    echo -e "${GREEN}[ Info ]${NC}     - Batch Processing Time: ${PROC_LATENCY} ms (${BATCH_SIZE} frames)"
                    echo -e "${GREEN}[ Info ]${NC}     - Per-frame Latency: ~${PROC_PER_FRAME} ms (amortized)"
                done
            fi
            
            # Overall single-stream latency
            BATCH_PROCESSING_TIME=$(LC_ALL=C awk -v b="${BATCH_SIZE}" -v f="${THROUGHPUT_PER_STREAM}" \
                'BEGIN { printf("%.2f", (b / f) * 1000) }')
            
            PER_FRAME_LATENCY=$(LC_ALL=C awk -v b="${BATCH_SIZE}" -v total="${BATCH_PROCESSING_TIME}" \
                'BEGIN { 
                    if (b > 0) {
                        printf "%.2f", total / b
                    } else {
                        printf "0"
                    }
                }')
            
            DECODE_TOTAL=$(LC_ALL=C awk -v d="${DECODE_AVG}" -v b="${BATCH_SIZE}" \
                'BEGIN { printf("%.2f", d * b) }')
            
            E2E_BATCH_LATENCY=$(LC_ALL=C awk -v d="${DECODE_TOTAL}" -v p="${BATCH_PROCESSING_TIME}" \
                'BEGIN { printf("%.2f", d + p + 5) }')
            
            echo ""
            echo -e "${GREEN}[ Info ]${NC} Single-Stream Latency (Batch Size: ${BATCH_SIZE}):"
            echo -e "${GREEN}[ Info ]${NC}   - Decode Latency: ~${DECODE_LATENCY} ms (per frame)"
            echo -e "${GREEN}[ Info ]${NC}   - Batch Processing Time: ${BATCH_PROCESSING_TIME} ms (${BATCH_SIZE} frames)"
            echo -e "${GREEN}[ Info ]${NC}   - Per-frame Latency: ~${PER_FRAME_LATENCY} ms (amortized in batch)"
            echo -e "${GREEN}[ Info ]${NC}   - End-to-End Batch Latency: ~${E2E_BATCH_LATENCY} ms"
            echo ""
            echo -e "${YELLOW}[INFO]${NC} Explanation:"
            echo -e "${YELLOW}[INFO]${NC}   - Each process handles multiple streams concurrently"
            echo -e "${YELLOW}[INFO]${NC}   - Per-process batch latency: time for one process to handle one batch"
            echo -e "${YELLOW}[INFO]${NC}   - Single-stream latency: time for one stream to process ${BATCH_SIZE} frames"
            
            # Store for summary
            AI_AVG="${BATCH_PROCESSING_TIME}"
            AI_MEDIAN="${BATCH_PROCESSING_TIME}"
            AI_MIN="${BATCH_PROCESSING_TIME}"
            AI_MAX="${BATCH_PROCESSING_TIME}"
        fi
        
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
            
            # Add latency information to summary if available
            if [[ "${ENABLE_AI}" == true && -n "${AI_AVG}" ]]; then
                echo "Latency Metrics:"
                echo "--------------------------------------"
                echo "Batch Size: ${BATCH_SIZE}"
                echo "Decode Latency: ~2-4 ms (H.265 720p, per frame)"
                echo ""
                
                # Per-process latency details
                if [[ ${NUM_PROCESSES} -gt 1 && ${#PROCESS_LATENCY_ARRAY[@]} -gt 0 ]]; then
                    echo "Per-Process Batch Latency:"
                    for i in "${!PROCESS_LATENCY_ARRAY[@]}"; do
                        proc_id=$((i + 1))
                        PROC_FPS="${PROCESS_FPS_ARRAY[$i]}"
                        PROC_LATENCY="${PROCESS_LATENCY_ARRAY[$i]}"
                        PROC_PER_FRAME=$(LC_ALL=C awk -v b="${BATCH_SIZE}" -v total="${PROC_LATENCY}" \
                            'BEGIN { printf "%.2f", total / b }')
                        echo "  Process ${proc_id}: ${PROC_LATENCY} ms (${PROC_FPS} fps, ~${PROC_PER_FRAME} ms/frame)"
                    done
                    echo ""
                fi
                
                echo "Single-Stream Latency:"
                echo "  Batch Processing Time: ${AI_AVG} ms (${BATCH_SIZE} frames per batch)"
                echo "  Per-frame Latency: ~${PER_FRAME_LATENCY} ms (amortized in batch)"
                echo "  End-to-End Batch Latency: ~${E2E_BATCH_LATENCY} ms"
                echo ""
                echo "Explanation:"
                echo "  - Per-process latency: one process handles one batch"
                echo "  - Single-stream latency: one stream processes ${BATCH_SIZE} frames"
                echo "  - Multiple streams share GPU pipeline stage processing"
                echo ""
            fi
            echo "GPU Monitoring:"
            echo "--------------------------------------"
            if [[ -f "${MONITOR_CSV}" ]]; then
                echo "Monitor Data (CSV): ${MONITOR_CSV}"
                if [[ -f "${RESULTS_DIR}/gpu_metrics_raw.json" ]]; then
                    echo "Monitor Data (JSON): ${RESULTS_DIR}/gpu_metrics_raw.json"
                fi
                # Calculate average GPU metrics
                AVG_GPU_UTIL=$(awk -F',' 'NR>1 && $4 ~ /^[0-9]+(\.[0-9]+)?$/ {sum+=$4; count++} END {if(count>0) printf("%.2f", sum/count); else print "N/A"}' "${MONITOR_CSV}")
                AVG_GPU_POWER=$(awk -F',' 'NR>1 && $5 ~ /^[0-9]+(\.[0-9]+)?$/ {sum+=$5; count++} END {if(count>0) printf("%.2f", sum/count); else print "N/A"}' "${MONITOR_CSV}")
                AVG_GPU_FREQ=$(awk -F',' 'NR>1 && $6 ~ /^[0-9]+(\.[0-9]+)?$/ {sum+=$6; count++} END {if(count>0) printf("%.0f", sum/count); else print "N/A"}' "${MONITOR_CSV}")
                AVG_MEM_USED=$(awk -F',' 'NR>1 && $9 ~ /^[0-9]+(\.[0-9]+)?$/ {sum+=$9; count++} END {if(count>0) printf("%.0f", sum/count); else print "N/A"}' "${MONITOR_CSV}")
                
                echo "  Average GPU Utilization: ${AVG_GPU_UTIL}%"
                echo "  Average GPU Power: ${AVG_GPU_POWER}W"
                echo "  Average GPU Frequency: ${AVG_GPU_FREQ}MHz"
                echo "  Average GPU Memory Used: ${AVG_MEM_USED}MiB"
            else
                echo "Monitor Data: Not available"
            fi
            echo ""
            echo "Pipeline:"
            echo "${PIPELINE}"
            echo ""
        } > "${SUMMARY_FILE}"
        
        # Append system information
        SYSTEM_INFO_SCRIPT="$(cd "$(dirname "$0")/../../../html" && pwd)/generate_system_info.sh"
        if [[ -f "${SYSTEM_INFO_SCRIPT}" ]]; then
            TEMP_SYSINFO="${RESULTS_DIR}/.system_info.json"
            bash "${SYSTEM_INFO_SCRIPT}" "${TEMP_SYSINFO}" >/dev/null 2>&1
            
            if [[ -f "${TEMP_SYSINFO}" ]]; then
                {
                    echo "System Information:"
                    echo "--------------------------------------"
                    if command -v python3 >/dev/null 2>&1; then
                        python3 -c "import json; data=json.load(open('${TEMP_SYSINFO}')); print(f\"  CPU: {data['system']['name']}\\n  OS: {data['system']['os']}\\n  Kernel: {data['system']['kernel']}\\n  GPU Driver: {data['compute']['gpu_driver']}\\n  VA-API: {data['compute']['vaapi_version']}\\n  DLStreamer: {data['software']['dlstreamer_version']}\\n  OpenVINO: {data['software']['openvino_version']}\\n  Docker: {data['software']['docker_version']}\")" 2>/dev/null
                    else
                        cat "${TEMP_SYSINFO}"
                    fi
                    echo ""
                } >> "${SUMMARY_FILE}"
                rm -f "${TEMP_SYSINFO}"
            fi
        fi
        
        echo ""
        echo -e "${GREEN}[SUCCESS]${NC} Results saved to: ${RESULTS_DIR}"
        
        # Return throughput per stream for auto-tune mode
        echo "${THROUGHPUT_PER_STREAM}"
        
    else
        echo -e "${RED}[ERROR]${NC} Could not parse throughput from log"
        exit 1
    fi
else
    echo -e "${RED}[ERROR]${NC} Log file not found"
    exit 1
fi

echo ""
