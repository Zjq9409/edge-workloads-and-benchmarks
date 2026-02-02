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

# Model paths (from convert_models.sh output in pipelines directory)
MODELS=(
    "/home/intel/media_ai/edge-workloads-and-benchmarks/pipelines/light/detection/yolov11n_640x640/INT8/yolo11n.xml"
    "/home/intel/media_ai/edge-workloads-and-benchmarks/pipelines/medium/detection/yolov5m_640x640/INT8/yolov5m-640_INT8.xml"
    "/home/intel/media_ai/edge-workloads-and-benchmarks/pipelines/heavy/detection/yolov11m_640x640/INT8/yolo11m.xml"
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
Usage: $0 [OPTIONS]

Options:
  -m <model>         Model XML path (e.g., /home/intel/models/yolo11n.xml)
  -d <device>        Device (e.g., GPU.0, GPU.1) (default: GPU.0)
  -g <gpu_card>      GPU card (e.g., card0, card1) (default: auto-detect)
  -b <batch_sizes>   Space-separated batch sizes (default: "1 4 8 16 32 64 128")
  -a                 Test all models in predefined list
  -h                 Show this help message

Examples:
  Test single model:
    $0 -m /home/intel/models/yolo11n_openvino_model/yolo11n.xml -d GPU.0

  Test all models:
    $0 -a -d GPU.0

  Custom batch sizes:
    $0 -m model.xml -b "1 8 32 128"

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
    elif [[ "${DEVICE}" == "GPU.1" ]]; then
        CARD_DEV="/dev/dri/card1"
        RENDER_DEV="/dev/dri/renderD129"
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
    local model_dir=$(dirname "$model_path")
    
    # Determine if it's INT8 model
    if [[ "$model_dir" == *"int8"* ]]; then
        model_name="${model_name}-int8"
    fi
    
    local log_file="${RESULTS_DIR}/${model_name}.log"
    local summary_file="${RESULTS_DIR}/${model_name}_summary.txt"
    
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
        
        # Start GPU monitoring for this batch size
        local gpu_csv="${RESULTS_DIR}/${model_name}_bs${bs}_gpu.csv"
        local gpu_monitor_pid=""
        if [[ -f "${gpu_monitor_script}" ]]; then
            bash "${gpu_monitor_script}" "${gpu_csv}" "${device_id}" 1 "${model_name}" "${bs}" &
            gpu_monitor_pid=$!
            sleep 2
        fi
        
        # Run benchmark_app in container
        docker exec "${CONTAINER_NAME}" bash -c \
            "benchmark_app -m ${model_path} --batch_size ${bs} -d ${DEVICE} -hint throughput -shape [${bs},3,640,640]" \
            >> "${log_file}" 2>&1
        
        # Stop GPU monitoring
        if [[ -n "${gpu_monitor_pid}" ]]; then
            kill "${gpu_monitor_pid}" 2>/dev/null || true
            sleep 1
            kill -9 "${gpu_monitor_pid}" 2>/dev/null || true
        fi
        
        echo "" >> "${log_file}"
        sleep 5
    done
    
    echo -e "${GREEN}[DONE]${NC} Model ${model_name} testing completed"
    
    # List GPU metric files
    local gpu_files=$(ls "${RESULTS_DIR}/${model_name}"_bs*_gpu.csv 2>/dev/null | wc -l)
    if [[ ${gpu_files} -gt 0 ]]; then
        echo "  GPU metrics: ${gpu_files} files saved"
    fi
    echo ""
    
    # Parse results and generate summary
    generate_summary "${log_file}" "${summary_file}" "${model_name}"
}

# Function to generate summary from log file
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
        local throughput=$(grep -A 20 "Batch Size: ${bs}" "${log_file}" | grep "Throughput:" | head -n1 | awk '{print $2}')
        local latency=$(grep -A 20 "Batch Size: ${bs}" "${log_file}" | grep "Median:" | head -n1 | awk '{print $2}')
        
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
    {
        echo "=========================================="
        echo "Combined Benchmark Summary"
        echo "=========================================="
        echo "Device: ${DEVICE}"
        echo "Timestamp: ${TIMESTAMP}"
        echo "Total Models: ${#MODELS[@]}"
        echo ""
    } > "${COMBINED_SUMMARY}"
    
    for model in "${MODELS[@]}"; do
        model_name=$(basename "$model" .xml)
        model_dir=$(dirname "$model")
        if [[ "$model_dir" == *"int8"* ]]; then
            model_name="${model_name}-int8"
        fi
        
        summary_file="${RESULTS_DIR}/${model_name}_summary.txt"
        if [[ -f "${summary_file}" ]]; then
            cat "${summary_file}" >> "${COMBINED_SUMMARY}"
            echo "" >> "${COMBINED_SUMMARY}"
        fi
    done
    
    echo "Combined summary: ${COMBINED_SUMMARY}"
    
else
    # Test single model
    test_model "${MODEL_PATH}"
fi

echo ""
echo -e "${GREEN}[SUCCESS]${NC} Results saved to: ${RESULTS_DIR}"
echo ""

# Display quick summary
echo -e "${BLUE}Quick Summary:${NC}"
for summary in "${RESULTS_DIR}"/*_summary.txt; do
    if [[ -f "${summary}" ]]; then
        echo ""
        cat "${summary}"
    fi
done

echo ""
