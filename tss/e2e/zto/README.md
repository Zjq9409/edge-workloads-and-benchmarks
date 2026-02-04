# AI Pipeline Benchmark

Full AI inference pipeline benchmark with video decode, object detection, tracking, and metadata processing using Intel® DL Streamer.

## Overview

This benchmark measures end-to-end AI pipeline performance including:
- Video decode (H.265)
- Object detection (YOLO models)
- Object tracking
- Metadata processing
- Optional MQTT publishing

Supports multi-process execution for high-density testing and automatic tuning to find optimal stream counts.

## Quick Start

```bash
# AI pipeline with FP32 model (32 streams, 4 processes)
./run_pipeline_benchmark.sh -n 32 -P 4 -d GPU.0 -b 32 -a 

# AI pipeline with INT8 model (higher performance)
./run_pipeline_benchmark.sh -n 48 -P 6 -d GPU.0 -b 32 -a -int8 

# Auto-tune mode (find maximum streams)
./run_pipeline_benchmark.sh -n 40 -d GPU.0 -b 32 -a -T
```

## Usage

```bash
./run_pipeline_benchmark.sh [OPTIONS]
```

### Common Options

For quick reference, these are the most frequently used options:

```
-n <num_streams>   Number of AI streams (default: 1)
-P <num_processes> Number of processes (default: 1)
-d <device>        GPU device: GPU.0, GPU.1 (default: GPU.0)
-b <batch_size>    Inference batch size (default: 1)
-i <duration>      Test duration in seconds (default: 120)
-a                 Enable AI inference (required for AI pipeline)
-int8              Use INT8 model (default: FP32)
-T                 Enable auto-tune mode
-h                 Show this help message
```

## Examples

### AI Pipeline - FP32 Model

Full pipeline with FP32 YOLO model (32 streams, batch size 32):

```bash
./run_pipeline_benchmark.sh -n 32 -P 4 -d GPU.0 -b 32 -a -i 120
```

### AI Pipeline - INT8 Model (High Performance)

INT8 quantized model for better throughput (48 streams):

```bash
./run_pipeline_benchmark.sh -n 48 -P 6 -d GPU.0 -b 32 -a -int8 -i 120
```

### Auto-Tune Mode

Automatically find maximum stream count:

```bash
# FP32 model
./run_pipeline_benchmark.sh -n 40 -d GPU.0 -b 32 -a -T

# INT8 model
./run_pipeline_benchmark.sh -n 50 -d GPU.0 -b 32 -a -int8 -T

# Custom FPS threshold
./run_pipeline_benchmark.sh -n 40 -d GPU.0 -b 32 -a -T -s 30
```

**Auto-Tune Process:**
1. Tests with initial stream count (short 20s test)
2. Increases streams by 10 until FPS drops below threshold
3. Fine-tunes with step size 2 when approaching limit
4. Reports maximum sustainable stream count


## Output

Results are saved to: `./benchmark_results_<streams>streams_<processes>proc_bs<batch>_<timestamp>/`

### Generated Files

- **summary.txt**: Complete performance summary with system info
- **benchmark.log**: Combined pipeline logs from all processes
- **process_*.log**: Individual process logs
- **gpu_monitor.csv**: GPU metrics from xpu-smi
- **gpu_metrics_main.png**: Main GPU metrics visualization (8 charts)
- **gpu_metrics_engines.png**: Engine usage visualization (10 charts)
- **gpu_metrics_raw.json**: Raw qmassa data (kernel 6.14.0-37-generic only)
- **qmassa_charts_*.svg**: SVG charts from qmassa (kernel 6.14.0-37-generic only)

### Summary Metrics

- **Average Total Throughput**: Aggregate FPS from all streams
- **Throughput per Stream**: Average FPS per stream (should stay ≥ target FPS)
- **Theoretical Stream Density**: Maximum streams at target FPS
- **GPU Metrics**: Average utilization, power, frequency, memory
- **System Information**: CPU, OS, kernel, GPU driver, DLStreamer, OpenVINO versions

## Pipeline Architecture

### Full AI Pipeline (with `-a` flag)

```
Video Decode → Detection → Tracking → Metadata → MQTT → FPS Counter
```

Detailed GStreamer pipeline:

```
multifilesrc → h265parse → vah265dec → vapostproc → 
gvadetect (YOLO) → gvatrack → gvametaconvert → 
gvapython → gvametapublish → gvafpscounter → fakesink
```

**Components:**
- **multifilesrc**: Loops video file
- **vah265dec**: Hardware H.265 decode
- **vapostproc**: GPU post-processing
- **gvadetect**: Object detection with YOLO model
  - Batch processing for efficiency
  - VA-API surface sharing (zero-copy)
- **gvatrack**: Zero-term imageless tracking
- **gvametaconvert**: JSON metadata generation
- **gvapython**: Custom metadata processing (optional)
- **gvametapublish**: MQTT publishing (optional)
- **gvafpscounter**: FPS measurement (starts after 100 frames)



## Model Selection

### FP32 Model (Default)
- Path: `/home/dlstreamer/work/model-conversion/models/yolo11n/yolo11n_fp32.xml`
- Better accuracy
- Lower throughput
- Use for: accuracy-critical applications

### INT8 Model (`-int8` flag)
- Path: `/home/dlstreamer/work/model-conversion/models/yolo11n/yolo11n_int8.xml`
- Quantized for performance
- 1.5-2x higher throughput
- Use for: high-density deployments

### Custom Model (`-m` flag)
Override with your own OpenVINO model:

```bash
./run_pipeline_benchmark.sh -n 32 -P 4 -d GPU.0 -b 32 -a \
  -m /path/to/custom_model.xml
```

## Batch Size Optimization

Batch size controls inference efficiency:

| Batch Size | Use Case | Typical Streams |
|------------|----------|-----------------|
| 1 | Low latency, real-time | 8-16 |
| 8-16 | Balanced | 16-32 |
| 32-64 | High throughput | 32-64 |
| 128+ | Maximum density | 64+ |

**Recommendations:**
- Start with batch size = streams / processes
- FP32: batch size 16-32
- INT8: batch size 32-64
- Monitor GPU utilization (target 90-100%)

## Multi-Process Execution

When using multiple processes (`-P` flag):

- Streams are evenly distributed across processes
- Each process runs independent gst-launch-1.0 instance
- Results aggregated from all processes
- Better GPU utilization at high stream counts

**Example:** 48 streams with 6 processes
- Process 1-6: 8 streams each
- Each process: independent inference instance
- Total throughput: sum of all processes

**Guidelines:**
- Use 1 process for ≤8 streams
- Use 4-6 processes for 32-48 streams
- About 8 streams per process is optimal

## GPU Monitoring

GPU monitoring runs automatically in the background:

### Metrics Collected (xpu-smi)
- GPU Utilization (%)
- GPU Power (W)
- GPU Frequency (MHz)
- GPU Temperature (°C)
- Memory Usage (MiB)
- Engine Utilization:
  - Compute Engine
  - Decoder Engines (0, 1)
  - Encoder Engines (0, 1)
  - Copy Engine
  - Media Enhancement Engines (0, 1)
- Media Engine Frequency (MHz)

### Additional Metrics (kernel 6.14.0-37-generic)
When running on kernel 6.14.0-37-generic, qmassa provides:
- Detailed engine breakdowns
- SVG visualizations
- Power usage over time
- Memory bandwidth metrics

### Visualization
Plots are automatically generated when benchmark completes:
- **gpu_metrics_main.png**: 8 primary metrics
- **gpu_metrics_engines.png**: 10 engine-specific metrics
- **qmassa_charts_*.svg**: Detailed SVG charts (kernel-specific)


## Related Scripts

- `../decode/run_decode_benchmark.sh`: Pure decode throughput testing
- `../ov_benchmark/run_model_benchmark.sh`: Model-only benchmarking
- `../utils/gpu_monitor.sh`: GPU monitoring utility
- `../model-conversion/`: Model conversion tools
