#!/bin/bash

# Enhanced Model Benchmark Script
# Run OpenVINO benchmark_app in container and collect statistics
# Reference: run_pipeline_benchmark.sh

set -e

# Examples:
# Test single model with default batch sizes:
#   ./run_model_benchmark.sh -m /home/intel/models/yolo11n_openvino_model/yolo11n.xml -d GPU.0

# Test all YOLO models:
#   ./run_model_benchmark.sh -a -d GPU.0

# Test with custom batch sizes:
#   ./run_model_benchmark.sh -m /home/intel/models/yolo11n_openvino_model/yolo11n.xml -d GPU.0 -b "1 4 8 16 32"

# Configuration
IMAGE="intel/dlstreamer:2025.2.0-ubuntu24"
MOUNT_DIR="/home/intel"
CONTAINER_NAME="model_benchmark_$$"
DEVICE="GPU.0"
BATCH_SIZES="1 4 8 16 32 64 128"
MODEL_PATH=""
TEST_ALL=false

# Model paths (from model-conversion/models directory)
MODELS=(
    "/home/intel/media_ai/edge-workloads-and-benchmarks/model-conversion/models/yolo11n/yolo11n_fp32.xml"
    "/home/intel/media_ai/edge-workloads-and-benchmarks/model-conversion/models/yolo11n/yolo11n_int8.xml"
)

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Usage
usage() {
    cat << EOF
OpenVINO Model Benchmark - Test model inference performance with GPU monitoring

Usage: $0 [OPTIONS]

Common options:
  -m <model>         Model XML path (required unless -a)
  -d <device>        GPU device: GPU.0, GPU.1 (default: GPU.0)
  -b <batch_sizes>   Space-separated batch sizes (default: "1 4 8 16 32 64 128")
  -a                 Test all predefined models
  -h                 Show this help message

Examples:
  ./run_model_benchmark.sh -m /home/intel/models/yolo11n.xml -d GPU.0
  ./run_model_benchmark.sh -a -d GPU.0
  ./run_model_benchmark.sh -m model.xml -b "1 8 32 128"

For detailed documentation, see: README.md

EOF
    exit 0
}

# Parse arguments
GPU_CARD=""
while getopts "m:d:g:b:ah" opt; do
    case $opt in
        m) MODEL_PATH="$OPTARG" ;;
        d) DEVICE="$OPTARG" ;;
        g) GPU_CARD="$OPTARG" ;;
        b) BATCH_SIZES="$OPTARG" ;;
        a) TEST_ALL=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate input
if [[ "${TEST_ALL}" == false && -z "${MODEL_PATH}" ]]; then
    echo -e "${RED}[ERROR]${NC} Please specify model path (-m) or use -a to test all models"
    usage
fi

# Results directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="./benchmark_results_${TIMESTAMP}"
mkdir -p "${RESULTS_DIR}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Model Benchmark${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Timestamp: ${TIMESTAMP}"
echo "Device: ${DEVICE}"
echo "Batch Sizes: ${BATCH_SIZES}"
if [[ "${TEST_ALL}" == true ]]; then
    echo "Mode: Test all models (${#MODELS[@]} models)"
else
    echo "Model: ${MODEL_PATH}"
fi
echo "Results: ${RESULTS_DIR}"
echo ""

# Detect GPU card and render device
if [[ -z "${GPU_CARD}" ]]; then
    if [[ "${DEVICE}" == "GPU.0" ]]; then
        CARD_DEV="/dev/dri/card0"
        RENDER_DEV="/dev/dri/renderD128"
    else
        CARD_DEV="/dev/dri/card0"
        RENDER_DEV="/dev/dri/renderD128"
    fi
else
    CARD_DEV="/dev/dri/${GPU_CARD}"
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

# Request sudo access upfront for GPU monitoring
echo -e "${YELLOW}[INFO]${NC} GPU monitoring requires sudo access. Please enter your password:"
sudo -v || {
    echo -e "${RED}[ERROR]${NC} Failed to obtain sudo access"
    exit 1
}

# Start container
echo -e "${YELLOW}[INFO]${NC} Creating container: ${CONTAINER_NAME}"
docker run -d \
    --name "${CONTAINER_NAME}" \
    --device="${CARD_DEV}" \
    --device="${RENDER_DEV}" \
    -v "${MOUNT_DIR}":/home/intel \
    -u root \
    "${IMAGE}" tail -f /dev/null >/dev/null

echo -e "${YELLOW}[INFO]${NC} Container created successfully"
echo ""

# Function to test a single model
test_model() {
    local model_path=$1
    local model_name=$(basename "$model_path" .xml)
    
    # Model name already contains fp32/int8 suffix, no need to add it again
    
    local log_file="${RESULTS_DIR}/${model_name}.log"
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Testing Model: ${model_name}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "Model Path: ${model_path}"
    echo "Log File: ${log_file}"
    echo ""
    
    # Write header to log file
    {
        echo "=========================================="
        echo "Model Benchmark: ${model_name}"
        echo "=========================================="
        echo "Model Path: ${model_path}"
        echo "Device: ${DEVICE}"
        echo "Timestamp: ${TIMESTAMP}"
        echo ""
    } > "${log_file}"
    
    # Extract device ID from DEVICE (e.g., GPU.0 -> 0)
    local device_id="${DEVICE##*.}"
    local gpu_monitor_script="$(cd "$(dirname "$0")/../utils" && pwd)/gpu_monitor.sh"
    
    # Test each batch size
    local batch_count=0
    local total_batches=$(echo ${BATCH_SIZES} | wc -w)
    
    for bs in ${BATCH_SIZES}; do
        batch_count=$((batch_count + 1))
        echo -e "${YELLOW}[${batch_count}/${total_batches}]${NC} Testing batch size: ${bs}"
        
        {
            echo "=========================================="
            echo "Batch Size: ${bs}"
            echo "=========================================="
        } >> "${log_file}"
        
        # Create batch-specific directory for GPU metrics
        local batch_results_dir="${RESULTS_DIR}/${model_name}_bs${bs}"
        mkdir -p "${batch_results_dir}"
        local gpu_csv="${batch_results_dir}/gpu_metrics.csv"
        local gpu_monitor_pid=""
        
        # Start GPU monitoring for this batch size
        if [[ -f "${gpu_monitor_script}" ]]; then
            bash "${gpu_monitor_script}" "${gpu_csv}" "${device_id}" 1 "${model_name}" "${bs}" "${batch_results_dir}" &
            gpu_monitor_pid=$!
            sleep 2
        fi
        
        # Run benchmark_app in container
        docker exec "${CONTAINER_NAME}" bash -c \
            "benchmark_app -m ${model_path} --batch_size ${bs} -d ${DEVICE} -hint throughput -shape [${bs},3,640,640]" \
            >> "${log_file}" 2>&1
        
        # Stop GPU monitoring (will auto-generate plots on exit)
        if [[ -n "${gpu_monitor_pid}" ]]; then
            kill "${gpu_monitor_pid}" 2>/dev/null || true
            wait "${gpu_monitor_pid}" 2>/dev/null || true
        fi
        
        echo "" >> "${log_file}"
        sleep 5
    done
    
    echo -e "${GREEN}[DONE]${NC} Model ${model_name} testing completed"
    
    # List GPU metric directories
    local gpu_dirs=$(ls -d "${RESULTS_DIR}/${model_name}"_bs* 2>/dev/null | wc -l)
    if [[ ${gpu_dirs} -gt 0 ]]; then
        echo "  GPU metrics: ${gpu_dirs} batch size results with plots"
        echo "  Results location: ${RESULTS_DIR}/${model_name}_bs*"
    fi
    echo ""
    
    # No longer generate individual summary files
}

# Function to parse results from log file (used by combined summary)
generate_summary() {
    local log_file=$1
    local summary_file=$2
    local model_name=$3
    
    {
        echo "=========================================="
        echo "Benchmark Summary: ${model_name}"
        echo "=========================================="
        echo "Device: ${DEVICE}"
        echo "Timestamp: ${TIMESTAMP}"
        echo ""
        echo "Results:"
        echo "--------------------------------------"
        printf "%-12s %-15s %-15s\n" "Batch Size" "Throughput(fps)" "Latency(ms)"
        echo "--------------------------------------"
    } > "${summary_file}"
    
    # Extract throughput and latency for each batch size
    for bs in ${BATCH_SIZES}; do
        # Find the section for this batch size
        # Format: [ INFO ] Throughput:   1302.37 FPS
        local throughput=$(grep -A 30 "Batch Size: ${bs}" "${log_file}" | grep "Throughput:" | head -n1 | awk '{print $4}')
        # Format: [ INFO ]    Median:        2.97 ms
        local latency=$(grep -A 30 "Batch Size: ${bs}" "${log_file}" | grep "Median:" | head -n1 | awk '{print $4}')
        
        if [[ -n "${throughput}" && -n "${latency}" ]]; then
            printf "%-12s %-15s %-15s\n" "${bs}" "${throughput}" "${latency}" >> "${summary_file}"
        fi
    done
    
    echo "" >> "${summary_file}"
    echo "Full log: ${log_file}" >> "${summary_file}"
}

# Main execution
if [[ "${TEST_ALL}" == true ]]; then
    echo -e "${YELLOW}[INFO]${NC} Starting benchmark for ${#MODELS[@]} models..."
    echo ""
    
    model_count=0
    for model in "${MODELS[@]}"; do
        model_count=$((model_count + 1))
        echo -e "${GREEN}[${model_count}/${#MODELS[@]}]${NC} Processing model..."
        test_model "${model}"
    done
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}All Models Testing Completed${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    # Generate combined summary
    COMBINED_SUMMARY="${RESULTS_DIR}/all_models_summary.txt"
    
    # Collect system information first
    SYSTEM_INFO_SCRIPT="$(cd "$(dirname "$0")/../html" && pwd)/generate_system_info.sh"
    TEMP_SYSTEM_INFO="/tmp/system_info_$$.json"
    
    if [[ -f "${SYSTEM_INFO_SCRIPT}" ]]; then
        bash "${SYSTEM_INFO_SCRIPT}" "${TEMP_SYSTEM_INFO}" >/dev/null 2>&1
    fi
    
    {
        echo "=========================================="
        echo "Combined Benchmark Summary"
        echo "=========================================="
        echo "Device: ${DEVICE}"
        echo "Timestamp: ${TIMESTAMP}"
        echo "Total Models: ${#MODELS[@]}"
        echo ""
        
        # Add system information at the beginning
        if [[ -f "${TEMP_SYSTEM_INFO}" ]]; then
            echo "=========================================="
            echo "System Information"
            echo "=========================================="
            python3 -c "
import json
import sys
try:
    with open('${TEMP_SYSTEM_INFO}', 'r') as f:
        data = json.load(f)
    print(f\"CPU: {data['system']['name']}\")
    print(f\"OS: {data['system']['os']}\")
    print(f\"Kernel: {data['system']['kernel']}\")
    print(f\"GPU Driver: {data['compute']['gpu_driver']}\")
    print(f\"VA-API: {data['compute']['vaapi_version']}\")
    print(f\"DLStreamer: {data['software']['dlstreamer_version']}\")
    print(f\"OpenVINO: {data['software']['openvino_version']}\")
except Exception as e:
    print(f'Error parsing system info: {e}', file=sys.stderr)
" 2>/dev/null || echo "System info parsing failed"
            rm -f "${TEMP_SYSTEM_INFO}"
            echo ""
        fi
        
    } > "${COMBINED_SUMMARY}"
    
    for model in "${MODELS[@]}"; do
        model_name=$(basename "$model" .xml)
        # Model name already contains fp32/int8 suffix
        
        log_file="${RESULTS_DIR}/${model_name}.log"
        if [[ -f "${log_file}" ]]; then
            {
                echo "=========================================="
                echo "Model: ${model_name}"
                echo "=========================================="
                echo "Results:"
                echo "--------------------------------------"
                printf "%-12s %-15s %-15s\n" "Batch Size" "Throughput(fps)" "Latency(ms)"
                echo "--------------------------------------"
            } >> "${COMBINED_SUMMARY}"
            
            # Extract throughput and latency for each batch size
            for bs in ${BATCH_SIZES}; do
                # Extract results after the "Batch Size: X" marker
                section=$(sed -n "/^Batch Size: ${bs}$/,/^Batch Size:/p" "${log_file}" | sed '$d')
                if [[ -z "$section" ]]; then
                    # If no next batch size marker, get until end of file
                    section=$(sed -n "/^Batch Size: ${bs}$/,\$p" "${log_file}")
                fi
                
                throughput=$(echo "$section" | grep "Throughput:" | awk '{print $5}')
                latency=$(echo "$section" | grep "Median:" | awk '{print $5}')
                
                if [[ -n "${throughput}" && -n "${latency}" ]]; then
                    printf "%-12s %-15s %-15s\n" "${bs}" "${throughput}" "${latency}" >> "${COMBINED_SUMMARY}"
                fi
            done
            
            echo "" >> "${COMBINED_SUMMARY}"
        fi
    done
    
    echo "Combined summary: ${COMBINED_SUMMARY}"
    
else
    # Test single model - also generate summary
    test_model "${MODEL_PATH}"
    
    # Generate summary for single model
    model_name=$(basename "${MODEL_PATH}" .xml)
    # Model name already contains fp32/int8 suffix
    
    SUMMARY_FILE="${RESULTS_DIR}/all_models_summary.txt"
    log_file="${RESULTS_DIR}/${model_name}.log"
    
    # Collect system information first
    SYSTEM_INFO_SCRIPT="$(cd "$(dirname "$0")/../html" && pwd)/generate_system_info.sh"
    TEMP_SYSTEM_INFO="/tmp/system_info_$$.json"
    
    if [[ -f "${SYSTEM_INFO_SCRIPT}" ]]; then
        bash "${SYSTEM_INFO_SCRIPT}" "${TEMP_SYSTEM_INFO}" >/dev/null 2>&1
    fi
    
    {
        echo "=========================================="
        echo "Benchmark Summary: ${model_name}"
        echo "=========================================="
        echo "Device: ${DEVICE}"
        echo "Timestamp: ${TIMESTAMP}"
        echo ""
        
        # Add system information at the beginning
        if [[ -f "${TEMP_SYSTEM_INFO}" ]]; then
            echo "=========================================="
            echo "System Information"
            echo "=========================================="
            python3 -c "
import json
import sys
try:
    with open('${TEMP_SYSTEM_INFO}', 'r') as f:
        data = json.load(f)
    print(f\"CPU: {data['system']['name']}\")
    print(f\"OS: {data['system']['os']}\")
    print(f\"Kernel: {data['system']['kernel']}\")
    print(f\"GPU Driver: {data['compute']['gpu_driver']}\")
    print(f\"VA-API: {data['compute']['vaapi_version']}\")
    print(f\"DLStreamer: {data['software']['dlstreamer_version']}\")
    print(f\"OpenVINO: {data['software']['openvino_version']}\")
except Exception as e:
    print(f'Error parsing system info: {e}', file=sys.stderr)
" 2>/dev/null || echo "System info parsing failed"
            rm -f "${TEMP_SYSTEM_INFO}"
            echo ""
        fi
        
        echo "Results:"
        echo "--------------------------------------"
        printf "%-12s %-15s %-15s\n" "Batch Size" "Throughput(fps)" "Latency(ms)"
        echo "--------------------------------------"
    } > "${SUMMARY_FILE}"
    
    # Extract throughput and latency for each batch size
    for bs in ${BATCH_SIZES}; do
        # Extract results after the "Batch Size: X" marker
        section=$(sed -n "/^Batch Size: ${bs}$/,/^Batch Size:/p" "${log_file}" | sed '$d')
        if [[ -z "$section" ]]; then
            # If no next batch size marker, get until end of file
            section=$(sed -n "/^Batch Size: ${bs}$/,\$p" "${log_file}")
        fi
        
        throughput=$(echo "$section" | grep "Throughput:" | awk '{print $5}')
        latency=$(echo "$section" | grep "Median:" | awk '{print $5}')
        
        if [[ -n "${throughput}" && -n "${latency}" ]]; then
            printf "%-12s %-15s %-15s\n" "${bs}" "${throughput}" "${latency}" >> "${SUMMARY_FILE}"
        fi
    done
    
    echo "" >> "${SUMMARY_FILE}"
fi

echo ""
echo -e "${GREEN}[SUCCESS]${NC} Results saved to: ${RESULTS_DIR}"
echo ""

# Display quick summary
echo -e "${BLUE}Quick Summary:${NC}"
if [[ -f "${RESULTS_DIR}/all_models_summary.txt" ]]; then
    echo ""
    cat "${RESULTS_DIR}/all_models_summary.txt"
fi

echo ""
