# OpenVINO Model Benchmark

Benchmark OpenVINO models using Intel's `benchmark_app` tool with comprehensive GPU monitoring and performance metrics collection.

## Overview

This benchmark tests OpenVINO model inference performance across different batch sizes, collecting detailed GPU metrics including utilization, power, frequency, and engine-specific usage statistics.

## Quick Start

```bash
# Test single model with default batch sizes (1,4,8,16,32,64,128)
./run_model_benchmark.sh -m /home/intel/models/yolo11n.xml -d GPU.0

# Test all predefined models
./run_model_benchmark.sh -a -d GPU.0
```

## Usage

```
./run_model_benchmark.sh [OPTIONS]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-m <model>` | Model XML path<br>Example: /home/intel/models/yolo11n.xml | required (unless -a) |
| `-d <device>` | GPU device: GPU.0, GPU.1 | GPU.0 |
| `-g <gpu_card>` | GPU card: card0, card1, etc.<br>(auto-detected from device if not specified) | auto-detect |
| `-b <batch_sizes>` | Space-separated batch sizes to test | "1 4 8 16 32 64 128" |
| `-a` | Test all models in predefined list | disabled |
| `-h` | Show help message | - |

## Examples

### Test Single Model

Test with default batch sizes (1,4,8,16,32,64,128):

```bash
./run_model_benchmark.sh -m /home/intel/models/yolo11n.xml -d GPU.0
```

### Test All Models

Test all predefined models in the MODELS array:

```bash
./run_model_benchmark.sh -a -d GPU.0
```

### Custom Batch Sizes

Test specific batch sizes only:

```bash
./run_model_benchmark.sh -m model.xml -b "1 8 32 128" -d GPU.0
```

You can modify the `MODELS` array in the script to add your own models.

## Output

Results are saved to: `./benchmark_results_<timestamp>/`

### Directory Structure

```
benchmark_results_20260203_150000/
├── {model_name}.log                          # Complete benchmark logs
├── {model_name}_summary.txt                  # Performance summary
├── {model_name}_bs1/                         # Batch size 1 results
│   ├── gpu_metrics.csv                       # GPU metrics (xpu-smi)
│   ├── gpu_metrics_main.png                  # Main GPU metrics chart
│   ├── gpu_metrics_engines.png               # Engine usage chart
│   ├── gpu_metrics_raw.json                  # Raw qmassa data (kernel 6.14.0-37-generic)
│   └── qmassa_charts_*.svg                   # SVG charts (kernel 6.14.0-37-generic)
├── {model_name}_bs4/                         # Batch size 4 results
│   └── ...
├── {model_name}_bs8/                         # Batch size 8 results
│   └── ...
└── all_models_summary.txt                    # Combined summary (when using -a)
```

### Summary Files

Each model gets a summary file with performance metrics:

```
==========================================
Benchmark Summary: yolo11n
==========================================
Device: GPU.0
Timestamp: 20260203_150000

Results:
--------------------------------------
Batch Size   Throughput(fps)  Latency(ms)
--------------------------------------
1            245.67           4.07
4            612.34           6.53
8            856.12           9.34
16           1024.45          15.62
32           1156.78          27.65
64           1203.22          53.18
128          1228.90          104.21
--------------------------------------
```


## Benchmark Configuration

The benchmark uses OpenVINO's `benchmark_app` with the following settings:

```bash
benchmark_app \
  -m <model.xml> \
  --batch_size <bs> \
  -d GPU.0 \
  -hint throughput \
  -shape [<bs>,3,640,640]
```

- **Mode**: Throughput optimization
- **Input Shape**: Dynamic based on batch size (assumes 640x640 YOLO models)
- **Device**: Intel GPU with hardware acceleration

## Understanding Results

### Throughput
- Measured in FPS (frames per second)
- Higher is better
- Typically increases with batch size until hardware limits

### Latency
- Measured in milliseconds (ms) per inference
- Lower is better for single-frame processing
- Increases with batch size

### GPU Utilization
- Target: 90-100% for optimal throughput
- Low utilization may indicate CPU bottleneck or suboptimal batch size

### Power Consumption
- Useful for efficiency analysis
- Compare power/throughput ratio across batch sizes

## Optimal Batch Size Selection

1. **Real-time Applications**: Use batch size 1 for lowest latency
2. **Throughput Applications**: Use larger batches (32-128) for maximum FPS
3. **Efficiency**: Find sweet spot where throughput/power is optimal
4. **Memory Constraints**: Monitor GPU memory usage, avoid OOM errors


## System Requirements

- **Container**: intel/dlstreamer:2025.2.0-ubuntu24
- **GPU**: Intel GPU with OpenVINO support
- **Software**: Docker, xpu-smi, OpenVINO toolkit
- **Permissions**: sudo access for GPU monitoring
- **Storage**: Sufficient space for models and results

## Model Format

Models must be in OpenVINO IR format:
- `.xml` - Model architecture
- `.bin` - Model weights

To convert models to OpenVINO format, see the `model-conversion` directory.