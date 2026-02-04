#!/bin/bash

# Decode-Only Benchmark Script
# Run GStreamer decode pipeline in container and collect statistics
# Focuses on pure decode throughput testing without AI inference

set -e

# Examples:
# Single process with 8 streams:
#   ./run_decode_benchmark.sh -v /home/dlstreamer/1280x720_25fps_medium.h265 -n 8 -d GPU.0 -i 120
#
# Multiple processes (8 streams in 2 processes):
#   ./run_decode_benchmark.sh -v /home/dlstreamer/1280x720_25fps_medium.h265 -n 8 -P 2 -d GPU.0 -i 120
#
# High density test (100 streams in 5 processes):
#   ./run_decode_benchmark.sh -v /home/dlstreamer/video.h265 -n 100 -P 5 -d GPU.1 -i 60

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
MOUNT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONTAINER_NAME="decode_benchmark_$$"
DURATION=120
TARGET_FPS=25
NUM_STREAMS=1
NUM_PROCESSES=1
USER_SET_PROCESSES=false
DEVICE="GPU.0"
VIDEO_FILE="/home/dlstreamer/work/media-downloader/media/hevc/apple_720p25_loop30.h265"
AUTO_TUNE=false
TUNE_THRESHOLD=25.0
TUNE_SHORT_DURATION=30

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Usage
usage() {
    cat << EOF
Decode-Only Benchmark - Tests pure video decode throughput without AI inference

Usage: $0 [OPTIONS]

Common options:
  -v <video>         Video file path (.h264, .h265, .mp4)
  -n <num_streams>   Number of decode streams (default: 1)
  -P <num_processes> Number of processes (default: 1)
  -d <device>        GPU device: GPU.0-GPU.3 (default: GPU.0)
  -i <duration>      Test duration in seconds (default: 120)
  -T                 Enable auto-tune mode
  -h                 Show this help message

Examples:
  ./run_decode_benchmark.sh -n 200 -P 4 -d GPU.0 -i 120
  ./run_decode_benchmark.sh -n 200 -d GPU.0 -T

For detailed documentation, see: README.md

EOF
    exit 0
}

# Parse arguments
GPU_CARD=""
while getopts "v:n:P:d:g:i:t:s:Th" opt; do
    case $opt in
        v) VIDEO_FILE="$OPTARG" ;;
        n) NUM_STREAMS="$OPTARG" ;;
        P) NUM_PROCESSES="$OPTARG"; USER_SET_PROCESSES=true ;;
        d) DEVICE="$OPTARG" ;;
        g) GPU_CARD="$OPTARG" ;;
        i) DURATION="$OPTARG" ;;
        t) TARGET_FPS="$OPTARG" ;;
        T) AUTO_TUNE=true ;;
        s) TUNE_THRESHOLD="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Auto-tune mode function
run_auto_tune() {
    local test_streams=$NUM_STREAMS
    local test_duration=$TUNE_SHORT_DURATION
    # Auto-calculate processes only if user didn't specify
    local processes=$NUM_PROCESSES
    if [[ "${USER_SET_PROCESSES}" == false ]]; then
        processes=$(( (test_streams + 49) / 50 ))
        [[ $processes -lt 1 ]] && processes=1
    fi
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Auto-Tune Mode: Finding Maximum Decode Streams${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "Video: ${VIDEO_FILE}"
    echo "Test streams: ${test_streams}"
    echo "FPS threshold: ${TUNE_THRESHOLD}"
    echo "Test duration: ${test_duration}s"
    echo "Device: ${DEVICE}"
    echo ""
    
    echo -e "${YELLOW}[TUNE Step 1/2]${NC} Running quick test with ${test_streams} streams (${processes} processes, ${test_duration}s)..."
    
    # Step 1: Run quick benchmark test (disable auto-tune for recursive call)
    AUTO_TUNE=false DURATION=$test_duration NUM_STREAMS=$test_streams NUM_PROCESSES=$processes \
        bash "$0" -v "$VIDEO_FILE" -n $test_streams -P $processes \
        -d "$DEVICE" -i $test_duration -t "$TARGET_FPS" >/dev/null 2>&1
    
    # Find the most recent decode_results directory
    local result_dir=$(ls -td decode_results_${test_streams}streams_${processes}proc_* 2>/dev/null | head -1)
    
    if [[ -z "$result_dir" || ! -f "$result_dir/summary.txt" ]]; then
        echo -e "${RED}[TUNE]${NC} Failed to find result summary"
        exit 1
    fi
    
    # Extract metrics from summary.txt
    local per_stream_fps=$(grep "Per-Stream Average:" "$result_dir/summary.txt" | grep -oP '\K[0-9.]+(?= fps/stream)')
    local theoretical_streams=$(grep "Theoretical Stream Density:" "$result_dir/summary.txt" | grep -oP '\K[0-9]+(?= streams)')
    local total_throughput=$(grep "Total Decode Throughput:" "$result_dir/summary.txt" | grep -oP '\K[0-9.]+(?= fps)')
    
    if [[ -z "$per_stream_fps" || -z "$theoretical_streams" ]]; then
        echo -e "${RED}[TUNE]${NC} Failed to parse results"
        exit 1
    fi
    
    echo -e "${GREEN}[TUNE Step 1/2]${NC} Initial test complete:"
    echo "  - Tested: ${test_streams} streams @ ${per_stream_fps} fps/stream"
    echo "  - Total Throughput: ${total_throughput} fps"
    echo "  - Theoretical Max: ${theoretical_streams} streams"
    echo ""
    
    # Step 2: Calculate optimal processes for verification (50 streams per process)
    local verify_processes
    if [[ "${USER_SET_PROCESSES}" == true ]]; then
        verify_processes=$NUM_PROCESSES
        echo -e "${YELLOW}[TUNE Step 2/2]${NC} Running verification with ${theoretical_streams} streams (${verify_processes} processes [user-specified], ~$((theoretical_streams / verify_processes)) streams/process, 120s)..."
    else
        verify_processes=$(( (theoretical_streams + 49) / 50 ))
        [[ $verify_processes -lt 1 ]] && verify_processes=1
        echo -e "${YELLOW}[TUNE Step 2/2]${NC} Running verification with ${theoretical_streams} streams (${verify_processes} processes [auto-calculated], ~$((theoretical_streams / verify_processes)) streams/process, 120s)..."
    fi
    
    # Run verification benchmark (disable auto-tune for recursive call)
    AUTO_TUNE=false DURATION=120 NUM_STREAMS=$theoretical_streams NUM_PROCESSES=$verify_processes \
        bash "$0" -v "$VIDEO_FILE" -n $theoretical_streams -P $verify_processes \
        -d "$DEVICE" -i 120 -t "$TARGET_FPS"
    
    # Find verification results
    local verify_dir=$(ls -td decode_results_${theoretical_streams}streams_${verify_processes}proc_* 2>/dev/null | head -1)
    
    if [[ -z "$verify_dir" || ! -f "$verify_dir/summary.txt" ]]; then
        echo -e "${RED}[TUNE]${NC} Verification test failed"
        exit 1
    fi
    
    # Extract verification metrics
    local verify_fps=$(grep "Per-Stream Average:" "$verify_dir/summary.txt" | grep -oP '\K[0-9.]+(?= fps/stream)')
    local verify_total=$(grep "Total Decode Throughput:" "$verify_dir/summary.txt" | grep -oP '\K[0-9.]+(?= fps)')
    
    echo -e "${GREEN}[TUNE Step 2/2]${NC} Verification complete: ${verify_fps} fps/stream"
    
    # Step 3: Fine-tune if verification didn't meet threshold
    local final_streams=$theoretical_streams
    local final_fps=$verify_fps
    local final_total=$verify_total
    local final_dir=$verify_dir
    
    # Check if we need to fine-tune (per-stream FPS below threshold)
    local fps_check=$(awk -v fps="$verify_fps" -v threshold="$TUNE_THRESHOLD" 'BEGIN { print (fps < threshold) ? 1 : 0 }')
    
    if [[ $fps_check -eq 1 ]]; then
        echo ""
        echo -e "${YELLOW}[TUNE Step 3/3]${NC} Per-stream FPS (${verify_fps}) below threshold (${TUNE_THRESHOLD}), fine-tuning..."
        
        local current_streams=$((theoretical_streams - 1))
        local max_attempts=20  # Safety limit to avoid infinite loop
        local attempt=0
        
        while [[ $attempt -lt $max_attempts && $current_streams -gt 0 ]]; do
            attempt=$((attempt + 1))
            
            # Calculate processes for current stream count
            local tune_processes
            if [[ "${USER_SET_PROCESSES}" == true ]]; then
                tune_processes=$NUM_PROCESSES
            else
                tune_processes=$(( (current_streams + 49) / 50 ))
                [[ $tune_processes -lt 1 ]] && tune_processes=1
            fi
            
            echo -e "${YELLOW}[TUNE 3/${max_attempts}]${NC} Testing ${current_streams} streams (${tune_processes} processes)..."
            
            # Run test with current stream count
            AUTO_TUNE=false DURATION=120 NUM_STREAMS=$current_streams NUM_PROCESSES=$tune_processes \
                bash "$0" -v "$VIDEO_FILE" -n $current_streams -P $tune_processes \
                -d "$DEVICE" -i 120 -t "$TARGET_FPS" >/dev/null 2>&1
            
            # Find results
            local tune_dir=$(ls -td decode_results_${current_streams}streams_${tune_processes}proc_* 2>/dev/null | head -1)
            
            if [[ -z "$tune_dir" || ! -f "$tune_dir/summary.txt" ]]; then
                echo -e "${RED}[TUNE]${NC} Test failed, stopping fine-tune"
                break
            fi
            
            # Extract metrics
            local tune_fps=$(grep "Per-Stream Average:" "$tune_dir/summary.txt" | grep -oP '\K[0-9.]+(?= fps/stream)')
            local tune_total=$(grep "Total Decode Throughput:" "$tune_dir/summary.txt" | grep -oP '\K[0-9.]+(?= fps)')
            
            echo "  Result: ${tune_fps} fps/stream (${tune_total} fps total)"
            
            # Check if we met the threshold
            fps_check=$(awk -v fps="$tune_fps" -v threshold="$TUNE_THRESHOLD" 'BEGIN { print (fps >= threshold) ? 1 : 0 }')
            
            if [[ $fps_check -eq 1 ]]; then
                echo -e "${GREEN}[TUNE]${NC} ✓ Found optimal streams: ${current_streams} @ ${tune_fps} fps/stream"
                final_streams=$current_streams
                final_fps=$tune_fps
                final_total=$tune_total
                final_dir=$tune_dir
                break
            fi
            
            # Decrease stream count and continue
            current_streams=$((current_streams - 1))
        done
        
        if [[ $fps_check -eq 0 ]]; then
            echo -e "${YELLOW}[TUNE]${NC} Fine-tune completed, best result: ${final_streams} streams @ ${final_fps} fps/stream"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Auto-Tune Results (Decode)${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "Video: ${VIDEO_FILE}"
    echo "Device: ${DEVICE}"
    echo "FPS Threshold: ${TUNE_THRESHOLD}"
    echo ""
    echo "Initial Test (${test_streams} streams):"
    echo "  Per-Stream FPS: ${per_stream_fps} fps"
    echo "  Total Throughput: ${total_throughput} fps"
    echo ""
    echo "Final Result (${final_streams} streams):"
    echo "  Per-Stream FPS: ${final_fps} fps"
    echo "  Total Throughput: ${final_total} fps"
    echo "  Status: $(awk -v fps="$final_fps" -v threshold="$TUNE_THRESHOLD" 'BEGIN { print (fps >= threshold) ? "✓ PASS" : "✗ BELOW THRESHOLD" }')"
    echo ""
    echo "Results saved to: ${final_dir}"
    echo ""
    
    exit 0
}

# Check if auto-tune mode is enabled
if [[ "${AUTO_TUNE}" == true ]]; then
    # In auto-tune mode, video file is optional (use default)
    run_auto_tune
fi

# Validate required parameters
if [[ -z "${VIDEO_FILE}" ]]; then
    echo -e "${RED}[ERROR]${NC} Video file is required (-v option)"
    echo "Use -h for help"
    exit 1
fi

# Results directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="./decode_results_${NUM_STREAMS}streams_${NUM_PROCESSES}proc_${TIMESTAMP}"
mkdir -p "${RESULTS_DIR}"

LOG_FILE="${RESULTS_DIR}/benchmark.log"
SUMMARY_FILE="${RESULTS_DIR}/summary.txt"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Decode-Only Benchmark${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Timestamp: ${TIMESTAMP}"
echo "Device: ${DEVICE}"
echo "Video: ${VIDEO_FILE}"
echo "Streams: ${NUM_STREAMS}"
echo "Processes: ${NUM_PROCESSES}"
echo "Duration: ${DURATION}s"
echo "Target FPS: ${TARGET_FPS}"
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
    elif [[ "${DEVICE}" == "GPU.2" ]]; then
        CARD_DEV="/dev/dri/card2"
        RENDER_DEV="/dev/dri/renderD130"
    elif [[ "${DEVICE}" == "GPU.3" ]]; then
        CARD_DEV="/dev/dri/card3"
        RENDER_DEV="/dev/dri/renderD131"
    else
        echo -e "${RED}[ERROR]${NC} Invalid device: ${DEVICE}"
        echo "Valid devices: GPU.0, GPU.1, GPU.2, GPU.3"
        exit 1
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
    -v "${MOUNT_DIR}":/home/dlstreamer/work \
    -u root \
    "${IMAGE}" tail -f /dev/null >/dev/null

echo -e "${YELLOW}[INFO]${NC} Container created successfully"
echo ""

# Detect video codec from file extension
VIDEO_LOWER=$(echo "${VIDEO_FILE}" | tr '[:upper:]' '[:lower:]')
if [[ "${VIDEO_LOWER}" =~ \.h264$ ]]; then
    PARSER="h264parse"
    DECODER="vah264dec"
    CODEC="H.264"
elif [[ "${VIDEO_LOWER}" =~ \.h265$ ]]; then
    PARSER="h265parse"
    DECODER="vah265dec"
    CODEC="H.265"
elif [[ "${VIDEO_LOWER}" =~ \.mp4$ ]]; then
    # For MP4, we'll use qtdemux and need to check codec inside container
    PARSER="qtdemux ! h265parse"  # Assume H.265 by default for MP4
    DECODER="vah265dec"
    CODEC="MP4 (H.265)"
    echo -e "${YELLOW}[WARNING]${NC} MP4 detected, assuming H.265 codec"
else
    echo -e "${RED}[ERROR]${NC} Unsupported video format: ${VIDEO_FILE}"
    echo "Supported formats: .h264, .h265, .mp4"
    exit 1
fi

echo "Detected codec: ${CODEC}"
echo "Using parser: ${PARSER}"
echo "Using decoder: ${DECODER}"
echo ""

# Build decode-only pipeline
PIPELINE="multifilesrc location=${VIDEO_FILE} loop=true ! ${PARSER} ! ${DECODER} ! vapostproc ! \"video/x-raw(memory:VAMemory)\" ! queue ! gvafpscounter starting-frame=100 ! fakesink sync=false async=false"

# Calculate streams per process
STREAMS_PER_PROCESS=$(( (NUM_STREAMS + NUM_PROCESSES - 1) / NUM_PROCESSES ))

# Write pipeline information to log file
{
    echo "=========================================="
    echo "Decode Pipeline Configuration"
    echo "=========================================="
    echo "Video File: ${VIDEO_FILE}"
    echo "Codec: ${CODEC}"
    echo "GPU Device: ${DEVICE} (${CARD_DEV})"
    echo "Total Streams: ${NUM_STREAMS}"
    echo "Number of Processes: ${NUM_PROCESSES}"
    echo "Streams per Process: ~${STREAMS_PER_PROCESS}"
    echo "Test Duration: ${DURATION}s"
    echo ""
    echo "Single Stream Pipeline:"
    echo "${PIPELINE}"
    echo ""
    echo "=========================================="
    echo "Pipeline Output"
    echo "=========================================="
    echo ""
} > "${LOG_FILE}"

# Extract device ID from DEVICE (e.g., GPU.0 -> 0)
DEVICE_ID="${DEVICE##*.}"

# Request sudo access upfront for GPU monitoring
echo -e "${YELLOW}[INFO]${NC} GPU monitoring requires sudo access. Please enter your password:"
sudo -v || {
    echo -e "${RED}[ERROR]${NC} Failed to obtain sudo access"
    exit 1
}

# Start GPU monitoring
GPU_MONITOR_CSV="${RESULTS_DIR}/gpu_metrics.csv"
GPU_MONITOR_SCRIPT="$(cd "$(dirname "$0")/../utils" && pwd)/gpu_monitor.sh"
GPU_MONITOR_PID=""

if [[ -f "${GPU_MONITOR_SCRIPT}" ]]; then
    echo -e "${YELLOW}[INFO]${NC} Starting GPU monitoring (device ${DEVICE_ID})..."
    bash "${GPU_MONITOR_SCRIPT}" "${GPU_MONITOR_CSV}" "${DEVICE_ID}" 1 "decode" "${NUM_STREAMS}" "${RESULTS_DIR}" &
    GPU_MONITOR_PID=$!
    echo "  GPU monitor PID: ${GPU_MONITOR_PID}"
    sleep 2
else
    echo -e "${YELLOW}[WARNING]${NC} GPU monitor script not found: ${GPU_MONITOR_SCRIPT}"
fi

# Run benchmark in container with multiple processes
echo -e "${YELLOW}[INFO]${NC} Starting ${NUM_PROCESSES} decode process(es) with total ${NUM_STREAMS} streams (${DURATION}s)..."

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
    
    # Build pipeline for this process (repeat for each stream)
    PROC_PIPELINE=""
    for i in $(seq 1 "${STREAMS_THIS_PROCESS}"); do
        PROC_PIPELINE="${PROC_PIPELINE} ${PIPELINE}"
    done
    
    # Create process-specific log file
    PROC_LOG="${RESULTS_DIR}/process_${proc_id}.log"
    PROCESS_LOGS+=("${PROC_LOG}")
    
    echo "  - Process ${proc_id}: ${STREAMS_THIS_PROCESS} streams (streams ${START_STREAM}-${END_STREAM})"
    
    # Start process in background
    (
        timeout --preserve-status "${DURATION}s" \
            docker exec "${CONTAINER_NAME}" bash -c "gst-launch-1.0 ${PROC_PIPELINE}" \
            2>&1 | grep --line-buffered -E "(FpsCounter|Setting pipeline|ERROR|WARNING)" | grep -v "longjmp causes uninitialized stack frame"
    ) > "${PROC_LOG}" 2>&1 &
    
    PROCESS_PIDS+=($!)
    sleep 0.5
done

echo -e "${YELLOW}[INFO]${NC} Waiting for all decode processes to complete..."

# Wait for all processes to complete
for pid in "${PROCESS_PIDS[@]}"; do
    wait "${pid}" 2>/dev/null || true
done

# Stop GPU monitoring
if [[ -n "${GPU_MONITOR_PID}" ]]; then
    echo -e "${YELLOW}[INFO]${NC} Stopping GPU monitoring..."
    kill "${GPU_MONITOR_PID}" 2>/dev/null || true
    sleep 1
    kill -9 "${GPU_MONITOR_PID}" 2>/dev/null || true
    
    if [[ -f "${GPU_MONITOR_CSV}" ]]; then
        echo "  GPU metrics saved to: ${GPU_MONITOR_CSV}"
    fi
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
echo -e "${GREEN}=         Decode Performance          =${NC}"
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
                    echo -e "${RED}  ✗ Process ${proc_id}: No FPS data found${NC}"
                    FAILED_PROCESSES+=("${proc_id}")
                else
                    # Check if runtime meets minimum threshold
                    RUNTIME_OK=$(LC_ALL=C awk -v r="${PROC_RUNTIME}" -v m="${MIN_DURATION}" \
                        'BEGIN { print (r >= m) ? 1 : 0 }')
                    
                    if [[ ${RUNTIME_OK} -eq 0 ]]; then
                        echo -e "${RED}  ✗ Process ${proc_id}: Terminated early (${PROC_RUNTIME}s / ${DURATION}s expected)${NC}"
                        FAILED_PROCESSES+=("${proc_id}")
                    else
                        echo -e "${GREEN}  ✓ Process ${proc_id}: Completed (${PROC_RUNTIME}s)${NC}"
                    fi
                fi
            else
                echo -e "${RED}  ✗ Process ${proc_id}: Log file not found${NC}"
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
            echo "  - Decoder errors or crashes"
            echo "  - Container or Docker issues"
            echo ""
            echo "Suggestions:"
            echo "  - Reduce number of streams (-n)"
            echo "  - Try with fewer processes (-P)"
            echo "  - Check process logs in: ${RESULTS_DIR}/"
            echo "  - Verify video file is valid: ${VIDEO_FILE}"
            echo ""
            exit 1
        fi
        
        echo ""
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
        
        echo -e "${GREEN}  ✓ Process completed (${PROC_RUNTIME}s)${NC}"
        echo ""
        
        THROUGHPUT=$(grep 'FpsCounter' "${LOG_FILE}" | grep 'average' | tail -n1 | sed 's/.*total=//' | cut -d' ' -f1)
    fi
    
    if [[ -n "${THROUGHPUT}" && "${THROUGHPUT}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        THROUGHPUT_PER_STREAM=$(LC_ALL=C awk -v t="${THROUGHPUT}" -v n="${NUM_STREAMS}" \
            'BEGIN { printf("%.2f", t / n) }')
        
        THEORETICAL_STREAMS=$(LC_ALL=C awk -v t="${THROUGHPUT}" -v f="${TARGET_FPS}" \
            'BEGIN { printf("%d", int(t / f)) }')
        
        echo ""
        echo -e "${GREEN}[ Results ]${NC}"
        echo "  Total Decode Throughput: ${THROUGHPUT} fps"
        echo "  Per-Stream Average: ${THROUGHPUT_PER_STREAM} fps/stream"
        echo "  Theoretical Stream Density (@${TARGET_FPS} fps): ${THEORETICAL_STREAMS} streams"
        
        # Save summary
        {
            echo "======================================"
            echo "Decode Benchmark Summary"
            echo "======================================"
            echo "Timestamp: ${TIMESTAMP}"
            echo "Video File: ${VIDEO_FILE}"
            echo "Codec: ${CODEC}"
            echo "GPU Device: ${DEVICE}"
            echo "GPU Card: ${CARD_DEV}"
            echo "Number of Streams: ${NUM_STREAMS}"
            echo "Number of Processes: ${NUM_PROCESSES}"
            echo "Duration: ${DURATION}s"
            echo "Target FPS: ${TARGET_FPS}"
            echo ""
            echo "Results:"
            echo "--------------------------------------"
            echo "Total Decode Throughput: ${THROUGHPUT} fps"
            echo "Per-Stream Average: ${THROUGHPUT_PER_STREAM} fps/stream"
            echo "Theoretical Stream Density: ${THEORETICAL_STREAMS} streams"
            echo ""
            echo "Pipeline:"
            echo "${PIPELINE}"
            echo ""
        } > "${SUMMARY_FILE}"
        
        # Add system information to summary
        TEMP_SYSTEM_INFO="${RESULTS_DIR}/temp_system_info.json"
        if [[ -f "../html/generate_system_info.sh" ]]; then
            bash ../html/generate_system_info.sh "$TEMP_SYSTEM_INFO" > /dev/null 2>&1
            if [[ -f "$TEMP_SYSTEM_INFO" ]]; then
                {
                    echo ""
                    echo "System Information:"
                    echo "--------------------------------------"
                    python3 -c "
import json
try:
    with open('$TEMP_SYSTEM_INFO', 'r') as f:
        data = json.load(f)
    print(f\"  CPU: {data['system']['name']}\")
    print(f\"  OS: {data['system']['os']}\")
    print(f\"  Kernel: {data['system']['kernel']}\")
    print(f\"  GPU Driver: {data['compute']['gpu_driver']}\")
    print(f\"  VA-API: {data['compute']['vaapi_version']}\")
    print(f\"  DLStreamer: {data['software']['dlstreamer_version']}\")
    print(f\"  OpenVINO: {data['software']['openvino_version']}\")
    print(f\"  Docker: {data['software']['docker_version']}\")
except Exception as e:
    print(f'Error parsing system info: {e}')
" 2>/dev/null || cat "$TEMP_SYSTEM_INFO"
                } >> "${SUMMARY_FILE}"
                rm -f "$TEMP_SYSTEM_INFO"
            fi
        fi
        
        echo ""
        echo -e "${GREEN}[SUCCESS]${NC} Results saved to: ${RESULTS_DIR}"
        echo "  - Summary: ${SUMMARY_FILE}"
        echo "  - Full log: ${LOG_FILE}"
        if [[ -f "${GPU_MONITOR_CSV}" ]]; then
            echo "  - GPU metrics: ${GPU_MONITOR_CSV}"
        fi
        
    else
        echo -e "${RED}[ERROR]${NC} Could not parse throughput from log"
        echo "Check log file: ${LOG_FILE}"
        exit 1
    fi
else
    echo -e "${RED}[ERROR]${NC} Log file not found: ${LOG_FILE}"
    exit 1
fi

echo ""
