# Decode-Only Benchmark

Tests pure video decode throughput without AI inference, focusing on GPU hardware decode acceleration.

## Overview

This benchmark measures the maximum decode throughput of Intel GPUs using Intel® DL Streamer pipelines. It supports multi-process execution for high-density testing and automatic tuning to find optimal stream counts.

## Quick Start

```bash
# Basic decode test (200 streams, 4 processes, 120 seconds)
./run_decode_benchmark.sh -n 200 -P 4 -d GPU.0 

# Auto-tune mode (find maximum streams)
./run_decode_benchmark.sh -n 200 -d GPU.0 -T
```

## Usage

```
./run_decode_benchmark.sh [OPTIONS]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-v <video>` | Video file path (supported: .h264, .h265, .mp4) | apple_720p25_loop30.h265 |
| `-n <num_streams>` | Number of decode streams | 1 |
| `-P <num_processes>` | Number of gst-launch-1.0 processes<br>Streams are distributed across processes | 1 |
| `-d <device>` | GPU device: GPU.0, GPU.1, GPU.2, GPU.3 | GPU.0 |
| `-g <gpu_card>` | GPU card: card0, card1, etc.<br>(auto-detected from device if not specified) | auto-detect |
| `-i <duration>` | Test duration in seconds | 120 |
| `-t <target_fps>` | Target FPS for density calculation | 25 |
| `-T` | Enable auto-tune mode to find maximum stream count | disabled |
| `-s <threshold>` | FPS threshold for auto-tune mode | 25.0 |
| `-h` | Show help message | - |

## Examples

### Basic Decode Test

Single GPU decode with 200 streams across 4 processes:

```bash
./run_decode_benchmark.sh -n 200 -P 4 -d GPU.0 -i 120
```

### Multi-Process Decode

Distribute 200 streams across 2 processes (100 streams each):

```bash
./run_decode_benchmark.sh -n 200 -P 2 -d GPU.0 -i 120
```

### High Density Test

Test on GPU.1 with 200 streams in 5 processes:

```bash
./run_decode_benchmark.sh -n 200 -P 5 -d GPU.1 -i 60
```

### Custom Video File

Test with your own video file:

```bash
./run_decode_benchmark.sh -v /path/to/video.h265 -n 200 -P 4 -d GPU.0 -i 120
```

### Auto-Tune Mode

Automatically find the maximum number of decode streams your GPU can handle:

```bash
# Start with 200 streams estimate
./run_decode_benchmark.sh -n 200 -d GPU.0 -T

# With custom FPS threshold (30 fps)
./run_decode_benchmark.sh -n 200 -d GPU.1 -T -s 30

# With custom video
./run_decode_benchmark.sh -v video.h265 -n 200 -d GPU.0 -T
```

**Auto-Tune Process:**
1. Runs quick 30s test with initial stream count
2. Calculates theoretical maximum based on results
3. Runs 120s verification test with optimal stream count
4. Fine-tunes if needed to meet FPS threshold

## Output

Results are saved to: `./decode_results_<streams>streams_<processes>proc_<timestamp>/`

### Generated Files

- **summary.txt**: Performance summary with system information
- **benchmark.log**: Complete pipeline logs from all processes
- **process_*.log**: Individual process logs
- **gpu_metrics.csv**: GPU monitoring data (utilization, power, frequency, etc.)
- **gpu_metrics_main.png**: Main GPU metrics visualization (8 charts)
- **gpu_metrics_engines.png**: Engine-specific metrics visualization (10 charts)
- **gpu_metrics_raw.json**: Raw GPU metrics from qmassa (kernel 6.14.0-37-generic only)
- **qmassa_charts_*.svg**: SVG charts from qmassa (kernel 6.14.0-37-generic only)

### Summary Metrics

- **Total Decode Throughput**: Aggregate FPS from all streams
- **Per-Stream Average**: Average FPS per stream
- **Theoretical Stream Density**: Maximum streams at target FPS
- **GPU Metrics**: Average utilization, power, frequency, memory
- **System Information**: CPU, OS, kernel, GPU driver, VA-API, DLStreamer, OpenVINO versions

## Pipeline Details

The benchmark uses the following GStreamer pipeline for each stream:

```
multifilesrc location=<video> loop=true ! 
  <parser> ! 
  <decoder> ! 
  vapostproc ! 
  "video/x-raw(memory:VAMemory)" ! 
  queue ! 
  gvafpscounter starting-frame=100 ! 
  fakesink sync=false async=false
```

- **Parser**: h264parse or h265parse (auto-detected)
- **Decoder**: vah264dec or vah265dec (VA-API hardware acceleration)
- **vapostproc**: Video post-processing on GPU
- **gvafpscounter**: FPS measurement (starts counting after 100 frames warmup)
- **fakesink**: Null output (no display, pure throughput test)

## GPU Monitoring

GPU metrics are automatically collected during benchmarks:

### xpu-smi Metrics (All Kernels)
- GPU Utilization (%)
- GPU Power (W)
- GPU Frequency (MHz)
- GPU Temperature (°C)
- Memory Usage (MiB)
- Engine Utilization: Compute, Decoder, Encoder, Copy, Media Enhancement
- Media Engine Frequency (MHz)

### qmassa Metrics (Kernel 6.14.0-37-generic Only)
Additional detailed metrics and SVG visualizations when running on kernel 6.14.0-37-generic.

## Multi-Process Execution

When using multiple processes (`-P` flag):

- Streams are evenly distributed across processes
- Each process runs an independent gst-launch-1.0 instance
- Results are aggregated from all processes
- Useful for maximizing GPU utilization

**Example:** 200 streams with 4 processes
- Process 1: 50 streams (1-50)
- Process 2: 50 streams (51-100)
- Process 3: 50 streams (101-150)
- Process 4: 50 streams (151-200)

## System Requirements

- **Container**: intel/dlstreamer:2025.2.0-ubuntu24
- **GPU**: Intel GPU with VA-API support
- **Software**: Docker, xpu-smi
- **Permissions**: sudo access for GPU monitoring

## Supported Video Formats

- **H.264** (.h264): Uses h264parse + vah264dec
- **H.265/HEVC** (.h265): Uses h265parse + vah265dec
- **MP4** (.mp4): Assumes H.265 codec (uses qtdemux + h265parse + vah265dec)

## Troubleshooting

### No FPS Output
- Check video file path is accessible inside container
- Verify video codec is supported (H.264 or H.265)
- Review process logs in results directory

### Low Throughput
- Reduce number of streams
- Increase number of processes
- Check GPU utilization in metrics
- Verify correct GPU device is selected

### GPU Monitoring Failed
- Ensure xpu-smi is installed
- Verify sudo access is available
- Check GPU device ID matches installed hardware

### Container Issues
- Verify GPU devices exist: `ls -l /dev/dri/`
- Check Docker has access to GPU devices
- Ensure container image is pulled: `docker pull intel/dlstreamer:2025.2.0-ubuntu24`

## Performance Tips

1. **Start Conservative**: Begin with lower stream counts and scale up
2. **Use Auto-Tune**: Let the script find optimal settings automatically
3. **Multi-Process**: Use 4-5 processes for high stream counts (200+)
4. **Monitor GPU**: Check metrics to ensure GPU is fully utilized
5. **Test Duration**: Use 120s for accurate results, 30s for quick tests

