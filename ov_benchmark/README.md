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

### Different GPU

Test on GPU.1:

```bash
./run_model_benchmark.sh -m model.xml -d GPU.1
```

## Predefined Models

The script includes three predefined models (when using `-a` flag):

1. **Light**: YOLOv11n INT8 (640x640)
   - Path: `pipelines/light/detection/yolov11n_640x640/INT8/yolo11n.xml`
   
2. **Medium**: YOLOv5m INT8 (640x640)
   - Path: `pipelines/medium/detection/yolov5m_640x640/INT8/yolov5m-640_INT8.xml`
   
3. **Heavy**: YOLOv11m INT8 (640x640)
   - Path: `pipelines/heavy/detection/yolov11m_640x640/INT8/yolo11m.xml`

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

### GPU Metrics

For each batch size, comprehensive GPU metrics are collected:

#### xpu-smi Metrics (All Kernels)
- GPU Utilization (%)
- GPU Power (W)
- GPU Frequency (MHz)
- GPU Core/Memory Temperature (°C)
- Memory Usage (MiB)
- Engine Utilization:
  - Compute Engine
  - Decoder Engines (0, 1)
  - Encoder Engines (0, 1)
  - Copy Engine
  - Media Enhancement Engines (0, 1)
- Media Engine Frequency (MHz)

#### qmassa Metrics (Kernel 6.14.0-37-generic Only)
Additional detailed metrics with SVG visualizations including:
- Memory info charts
- Engine usage breakdown
- GT0/GT1 frequency charts
- Power usage over time
- Fan speed (if available)

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

## GPU Monitoring

GPU monitoring is automatically enabled and runs in the background during each batch test. The script:

1. Requests sudo access once at startup
2. Starts `gpu_monitor.sh` for each batch size test
3. Collects metrics every second
4. Automatically generates plots when test completes
5. Maintains sudo credentials throughout the entire test session

### Monitoring Output

After each batch size test completes, you'll see:

```
[GPU Monitor] Monitoring stopped, generating plots...
[GPU Monitor] ✓ GPU metrics plots generated successfully
[GPU Monitor]   - benchmark_results_xxx/yolo11n_bs8/gpu_metrics_main.png
[GPU Monitor]   - benchmark_results_xxx/yolo11n_bs8/gpu_metrics_engines.png
[GPU Monitor] Average Metrics:
[GPU Monitor]   GPU Utilization: 95.34%
[GPU Monitor]   GPU Power: 48.23W
[GPU Monitor]   GPU Frequency: 2050MHz
```

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

## Troubleshooting

### Container Issues
- Verify GPU devices: `ls -l /dev/dri/`
- Check container image: `docker pull intel/dlstreamer:2025.2.0-ubuntu24`
- Ensure Docker has GPU access

### Model Loading Errors
- Verify model path is correct and accessible
- Check both `.xml` and `.bin` files exist
- Ensure model is compatible with OpenVINO version

### GPU Monitoring Failed
- Confirm xpu-smi is installed: `which xpu-smi`
- Verify sudo access works: `sudo -v`
- Check GPU device ID matches hardware

### Low Throughput
- Check GPU utilization in metrics
- Verify correct device is selected (GPU.0 vs GPU.1)
- Try different batch sizes
- Monitor for thermal throttling in GPU metrics

### Out of Memory
- Reduce batch size
- Check GPU memory usage in metrics
- Consider model optimization/quantization

## Performance Optimization Tips

1. **Batch Size Tuning**
   - Start with small batches and increase
   - Monitor memory usage
   - Find optimal throughput/latency balance

2. **Model Optimization**
   - Use INT8 quantization for better throughput
   - Consider model pruning
   - Optimize input resolution if possible

3. **System Tuning**
   - Ensure adequate cooling
   - Check power settings
   - Monitor thermal throttling in GPU metrics

4. **Multiple GPUs**
   - Test each GPU separately with `-d GPU.0`, `-d GPU.1`, etc.
   - Compare performance across devices
   - Distribute workload accordingly

## Related Scripts

- `../decode/run_decode_benchmark.sh`: Video decode throughput testing
- `../zto/run_pipeline_benchmark.sh`: Full AI pipeline benchmark
- `../utils/gpu_monitor.sh`: GPU monitoring utility
- `../model-conversion/`: Model conversion tools
