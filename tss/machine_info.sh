#!/bin/bash
# Machine Configuration Detection Script

DIVIDER="============================================================"

echo "$DIVIDER"
echo "  Machine Configuration Report - $(date '+%Y-%m-%d %H:%M:%S')"
echo "$DIVIDER"

# ---------- CPU ----------
echo ""
echo "[ CPU Information ]"

CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | awk -F': ' '{print $2}')
echo "  Model       : ${CPU_MODEL}"

PHYSICAL_CORES=$(grep "^cpu cores" /proc/cpuinfo | head -1 | awk '{print $NF}')
SOCKETS=$(grep "^physical id" /proc/cpuinfo | sort -u | wc -l)
LOGICAL_CORES=$(nproc)
TOTAL_PHYSICAL=$((PHYSICAL_CORES * SOCKETS))
echo "  Sockets     : ${SOCKETS}"
echo "  Physical cores (per socket): ${PHYSICAL_CORES}"
echo "  Physical cores (total)     : ${TOTAL_PHYSICAL}"
echo "  Logical cores (threads)    : ${LOGICAL_CORES}"

BASE_FREQ=$(grep -m1 "cpu MHz" /proc/cpuinfo | awk '{printf "%.0f MHz", $NF}')
echo "  Current freq: ${BASE_FREQ}"

MAX_FREQ_FILE="/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"
BASE_FREQ_FILE="/sys/devices/system/cpu/cpu0/cpufreq/base_frequency"
if [ -f "$MAX_FREQ_FILE" ]; then
    MAX_FREQ_KHZ=$(cat "$MAX_FREQ_FILE")
    echo "  Max freq    : $((MAX_FREQ_KHZ / 1000)) MHz"
fi
if [ -f "$BASE_FREQ_FILE" ]; then
    BASE_FREQ_KHZ=$(cat "$BASE_FREQ_FILE")
    echo "  Base freq   : $((BASE_FREQ_KHZ / 1000)) MHz"
fi

L3_CACHE=$(grep -m1 "cache size" /proc/cpuinfo | awk -F': ' '{print $2}')
echo "  L3 Cache    : ${L3_CACHE}"

# ---------- Memory ----------
echo ""
echo "[ Memory Information ]"

TOTAL_MEM_KB=$(grep "^MemTotal" /proc/meminfo | awk '{print $2}')
TOTAL_MEM_GB=$(awk "BEGIN {printf \"%.1f GB\", $TOTAL_MEM_KB/1048576}")
FREE_MEM_KB=$(grep "^MemFree" /proc/meminfo | awk '{print $2}')
FREE_MEM_GB=$(awk "BEGIN {printf \"%.1f GB\", $FREE_MEM_KB/1048576}")
AVAIL_MEM_KB=$(grep "^MemAvailable" /proc/meminfo | awk '{print $2}')
AVAIL_MEM_GB=$(awk "BEGIN {printf \"%.1f GB\", $AVAIL_MEM_KB/1048576}")

echo "  Total       : ${TOTAL_MEM_GB}"
echo "  Free        : ${FREE_MEM_GB}"
echo "  Available   : ${AVAIL_MEM_GB}"

if command -v dmidecode &>/dev/null; then
    DMIDECODE_OUT=$(sudo dmidecode -t memory 2>/dev/null)
    if [ -n "$DMIDECODE_OUT" ]; then
        MEM_TYPE=$(echo "$DMIDECODE_OUT" | grep -m1 "^\s*Type:" | grep -v "Unknown" | awk -F': ' '{print $2}' | xargs)
        MEM_SPEED=$(echo "$DMIDECODE_OUT" | grep -m1 "Configured Memory Speed:" | awk -F': ' '{print $2}' | xargs)
        MEM_SLOTS_TOTAL=$(echo "$DMIDECODE_OUT" | grep -c "Memory Device")
        MEM_SLOTS_USED=$(echo "$DMIDECODE_OUT" | grep "^\s*Size:" | grep -v "No Module" | wc -l)
        DIMM_SIZE=$(echo "$DMIDECODE_OUT" | grep "^\s*Size:" | grep -v "No Module" | head -1 | awk '{print $2, $3}')

        [ -n "$MEM_TYPE" ]  && echo "  Type        : ${MEM_TYPE}"
        [ -n "$MEM_SPEED" ] && echo "  Speed       : ${MEM_SPEED}"
        [ -n "$DIMM_SIZE" ] && echo "  DIMM size   : ${DIMM_SIZE} (per slot)"
        echo "  Slots used  : ${MEM_SLOTS_USED} / ${MEM_SLOTS_TOTAL}"
    else
        echo "  (dmidecode requires sudo for DIMM details)"
    fi
else
    echo "  (install dmidecode for DIMM type/speed details)"
fi

# ---------- GPU ----------
echo ""
echo "[ GPU Information ]"

GPU_FOUND=0

# NVIDIA GPU
if command -v nvidia-smi &>/dev/null; then
    NVIDIA_OUT=$(nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader 2>/dev/null)
    if [ -n "$NVIDIA_OUT" ]; then
        GPU_FOUND=1
        NVIDIA_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
        echo "  Vendor      : NVIDIA"
        echo "  Driver      : ${NVIDIA_DRIVER}"
        while IFS=',' read -r idx name mem; do
            name=$(echo "$name" | xargs)
            mem=$(echo "$mem" | xargs)
            echo "  GPU ${idx}      : ${name} (${mem})"
        done <<< "$NVIDIA_OUT"
    fi
fi

# Intel GPU
XPU_DEVICES=""
if command -v xpu-smi &>/dev/null; then
    XPU_DEVICES=$(xpu-smi discovery 2>/dev/null | grep -E "Device Name|Driver Version")
fi
if [ -n "$XPU_DEVICES" ]; then
    GPU_FOUND=1
    echo "  Vendor      : Intel (xpu-smi)"
    INTEL_DRIVER=$(modinfo i915 2>/dev/null | grep "^version:" | awk '{print $2}')
    [ -n "$INTEL_DRIVER" ] && echo "  i915 driver : ${INTEL_DRIVER}"
    echo "$XPU_DEVICES" | sed 's/^/  /'
elif lspci 2>/dev/null | grep -qi "intel.*\(VGA\|3D controller\)"; then
    INTEL_GPUS=$(lspci 2>/dev/null | grep -i intel | grep -iE "VGA|3D controller")
    if [ -n "$INTEL_GPUS" ]; then
        GPU_FOUND=1
        echo "  Vendor      : Intel"
        INTEL_DRIVER=$(modinfo i915 2>/dev/null | grep "^version:" | awk '{print $2}' || cat /sys/module/i915/version 2>/dev/null)
        [ -n "$INTEL_DRIVER" ] && echo "  i915 driver : ${INTEL_DRIVER}"
        echo "$INTEL_GPUS" | while read -r line; do echo "  GPU       : $line"; done
    fi
fi

[ "$GPU_FOUND" -eq 0 ] && echo "  No NVIDIA or Intel GPU detected"

# ---------- OS / Kernel ----------
echo ""
echo "[ OS / Kernel ]"
echo "  OS          : $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"')"
echo "  Kernel      : $(uname -r)"
echo "  Architecture: $(uname -m)"

echo ""
echo "$DIVIDER"

