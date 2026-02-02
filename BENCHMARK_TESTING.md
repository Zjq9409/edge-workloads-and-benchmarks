# Benchmark Testing Guide

本文档介绍如何使用两个独立的基准测试工具来评估系统性能。

## 目录
- [模型推理性能测试 (OpenVINO)](#模型推理性能测试-openvino)
- [视频解码性能测试](#视频解码性能测试)

---

## 模型推理性能测试 (OpenVINO)

### 概述
使用 OpenVINO benchmark_app 测试深度学习模型的推理性能，支持不同批次大小和多种 YOLO 模型。

### 脚本位置
```bash
/home/intel/media_ai/edge-workloads-and-benchmarks/ov_benchmark/run_model_benchmark.sh
```

### 功能特性
- 支持单个模型或批量测试多个预定义模型
- 可自定义批次大小（默认: 1, 4, 8, 16, 32, 64, 128）
- 支持多GPU设备选择（GPU.0, GPU.1等）
- 自动生成详细的性能报告和日志
- 集成 GPU 监控（功耗、利用率、温度等）

### 命令参数

| 参数 | 说明 | 默认值 | 示例 |
|-----|------|-------|------|
| `-m` | 模型 XML 路径 | 无 | `/home/intel/models/yolo11n.xml` |
| `-d` | 推理设备 | `GPU.0` | `GPU.0`, `GPU.1` |
| `-g` | GPU 卡号 | 自动检测 | `card0`, `card1` |
| `-b` | 批次大小列表 | `"1 4 8 16 32 64 128"` | `"1 8 32"` |
| `-a` | 测试所有预定义模型 | false | - |
| `-h` | 显示帮助信息 | - | - |

### 使用示例

#### 1. 测试单个模型（默认批次大小）
```bash
cd /home/intel/media_ai/edge-workloads-and-benchmarks/ov_benchmark
./run_model_benchmark.sh -m /home/intel/models/yolo11n_openvino_model/yolo11n.xml -d GPU.0
```

#### 2. 测试所有预定义的 YOLO 模型
```bash
./run_model_benchmark.sh -a -d GPU.0
```

预定义模型包括：
- YOLOv11n (light 配置)
- YOLOv5m (medium 配置)
- YOLOv11m (heavy 配置)

#### 3. 自定义批次大小
```bash
./run_model_benchmark.sh -m model.xml -d GPU.0 -b "1 8 32 128"
```

#### 4. 指定特定 GPU 卡
```bash
./run_model_benchmark.sh -m model.xml -d GPU.1 -g card1
```

### 输出结果

测试结果保存在 `benchmark_results_<timestamp>/` 目录中：

```
benchmark_results_20260202_143000/
├── yolo11n.log              # 完整的测试日志
├── yolo11n_summary.txt      # 性能摘要
├── yolo11n-int8.log         # INT8 模型日志
└── yolo11n-int8_summary.txt # INT8 模型摘要
```

**性能摘要示例：**
```
Model: yolo11n
Batch Size: 32
Throughput: 1245.67 FPS
Latency: 25.68 ms
GPU Utilization: 98.5%
Power: 45.2 W
```

---

## 视频解码性能测试

### 概述
测试纯视频解码（无 AI 推理）的吞吐量性能，支持单进程/多进程、多流解码，并提供自动调优功能。

### 脚本位置
```bash
/home/intel/media_ai/edge-workloads-and-benchmarks/decode/run_decode_benchmark.sh
```

### 功能特性
- 纯硬件加速视频解码测试（GPU VA-API）
- 支持 H.264/H.265 视频格式
- 单进程或多进程并发测试
- 自动调优模式：自动找到最大解码流数量
- 实时 FPS 和流密度统计
- 集成 GPU 监控

### 命令参数

| 参数 | 说明 | 默认值 | 示例 |
|-----|------|-------|------|
| `-v` | 视频文件路径 | `apple_720p25_loop30.h265` | `video.h265` |
| `-n` | 解码流数量 | `1` | `200` |
| `-P` | 进程数量 | `1` | `4` |
| `-d` | GPU 设备 | `GPU.0` | `GPU.0`, `GPU.1` |
| `-g` | GPU 卡号 | 自动检测 | `card0`, `card1` |
| `-i` | 测试时长（秒） | `120` | `60` |
| `-t` | 目标 FPS（用于密度计算） | `25` | `30` |
| `-T` | 启用自动调优模式 | false | - |
| `-s` | 自动调优 FPS 阈值 | `25.0` | `30.0` |
| `-h` | 显示帮助信息 | - | - |

### 使用示例

#### 1. 基础解码测试（200流，单进程，120秒）
```bash
cd /home/intel/media_ai/edge-workloads-and-benchmarks/decode
./run_decode_benchmark.sh -n 200 -d GPU.0 -i 120
```

#### 2. 多进程解码（200流，4进程，120秒）
```bash
./run_decode_benchmark.sh -n 200 -P 4 -d GPU.0 -i 120
```

**进程分配：** 200流 ÷ 4进程 = 每进程50流

#### 3. 自定义视频文件测试
```bash
./run_decode_benchmark.sh -v /path/to/video.h265 -n 100 -d GPU.0 -i 60
```

#### 4. 自动调优模式（自动找到最大流数）
```bash
# 基础自动调优（从80流开始测试）
./run_decode_benchmark.sh -n 80 -d GPU.0 -T

# 高级自动调优（指定视频和FPS阈值）
./run_decode_benchmark.sh -v video.h265 -n 200 -d GPU.1 -T -s 30
```

**自动调优工作流程：**
1. **快速测试** (30秒)：测试初始流数量，获得单流 FPS
2. **验证测试** (120秒)：根据理论计算测试最大流数
3. **精细调优** (可选)：如果未达到 FPS 阈值，自动递减流数重新测试

#### 5. 多GPU测试（GPU.1）
```bash
./run_decode_benchmark.sh -n 200 -P 4 -d GPU.1 -i 120
```

#### 6. 高密度测试（500流，10进程）
```bash
./run_decode_benchmark.sh -n 500 -P 10 -d GPU.0 -i 60
```

### 输出结果

测试结果保存在 `decode_results_<streams>streams_<processes>proc_<timestamp>/` 目录中：

```
decode_results_200streams_4proc_20260202_143530/
├── benchmark.log       # 完整的 GStreamer 管道日志
├── process_0.log       # 进程 0 的日志
├── process_1.log       # 进程 1 的日志
├── process_2.log       # 进程 2 的日志
├── process_3.log       # 进程 3 的日志
├── summary.txt         # 性能摘要
└── gpu_stats.log       # GPU 监控数据（如果可用）
```

**性能摘要示例 (summary.txt)：**
```
========================================
Decode Benchmark Summary
========================================
Video: apple_720p25_loop30.h265
Streams: 200
Processes: 4
Device: GPU.0
Duration: 120s

----------------------------------------
Performance Metrics
----------------------------------------
Total Decode Throughput: 4850.23 fps
Per-Stream Average: 24.25 fps/stream
Target FPS: 25.0 fps
Theoretical Stream Density: 194 streams

----------------------------------------
Process Distribution
----------------------------------------
Process 0: 50 streams @ 24.32 fps/stream
Process 1: 50 streams @ 24.28 fps/stream
Process 2: 50 streams @ 24.21 fps/stream
Process 3: 50 streams @ 24.19 fps/stream

----------------------------------------
GPU Statistics (Average)
----------------------------------------
GPU Utilization: 97.5%
GPU Power: 52.3 W
GPU Memory: 8.2 GB
GPU Temperature: 68.5°C
```

---

## 性能优化建议

### 模型推理测试优化
1. **批次大小选择**：根据延迟要求选择合适的批次大小
   - 低延迟：batch size = 1-4
   - 高吞吐：batch size = 32-128
2. **GPU 利用率**：目标保持在 90%+ 以获得最佳性能
3. **多模型测试**：使用 `-a` 参数对比不同模型的性能表现

### 视频解码测试优化
1. **进程数量**：建议每 50-80 流使用 1 个进程
   - 过多进程：增加调度开销
   - 过少进程：单进程流数过多可能影响性能
2. **自动调优**：首次测试使用 `-T` 参数自动找到最优配置
3. **FPS 阈值**：根据视频源帧率设置合理阈值（如 25fps 视频设置 `-s 24`）
4. **测试时长**：
   - 快速验证：60秒
   - 稳定性测试：120秒+

### 多GPU系统建议
- GPU.0 和 GPU.1 可并行测试
- 注意热管理和功耗限制
- 使用 `-g` 参数明确指定 GPU 卡号避免冲突

---

## 常见问题

### Q1: 如何选择进程数量？
**A:** 建议公式：`processes = (streams + 49) / 50`
- 100 流 → 2 进程
- 200 流 → 4 进程
- 500 流 → 10 进程

### Q2: 自动调优模式失败怎么办？
**A:** 
1. 减少初始流数量（`-n` 参数）
2. 降低 FPS 阈值（`-s` 参数）
3. 手动指定进程数（`-P` 参数）

### Q3: GPU 利用率低怎么办？
**A:**
- 模型推理：增加批次大小
- 视频解码：增加流数量或减少进程数

### Q4: 如何测试特定分辨率的视频？
**A:** 
1. 使用 `media-downloader/download_and_encode.sh` 生成指定分辨率视频
2. 使用 `-v` 参数指定视频路径

### Q5: 测试结果在哪里？
**A:**
- 模型推理：`ov_benchmark/benchmark_results_<timestamp>/`
- 视频解码：`decode/decode_results_<params>_<timestamp>/`

---

## 相关文档
- [主 README](README.md) - 完整的 pipeline 测试指南
- [模型转换指南](model-conversion/README.md) - 如何转换和量化模型
- [媒体下载指南](media-downloader/README.md) - 如何准备测试视频

---

## 技术支持
如遇问题，请检查：
1. Docker 是否正确安装并运行
2. GPU 驱动是否正确安装（VA-API 支持）
3. `/dev/dri/` 设备是否可访问
4. 视频文件路径是否正确

**日志位置：**
- 容器日志：`docker logs <container_name>`
- 测试日志：结果目录中的 `.log` 文件
