# 综合指标提取脚本使用说明

## 脚本功能

`extract_comprehensive_metrics.py` 可以从benchmark结果目录中同时提取性能指标和显存使用情况，生成综合的CSV报告。

## 提取的指标

1. **性能指标**（从日志文件提取）：
   - 模型名称
   - Batch Size
   - 吞吐量(FPS)
   - 延迟-中位数(ms)
   - 延迟-平均(ms)
   - 延迟-最小(ms)
   - 延迟-最大(ms)

2. **显存指标**（从gpu_metrics.csv提取）：
   - 峰值显存使用(MiB) - GPU运行时的最大显存占用

## 使用方法

### 基本用法

```bash
# 处理默认目录
python3 extract_comprehensive_metrics.py

# 处理指定目录
python3 extract_comprehensive_metrics.py /path/to/benchmark_results
```

### 示例

```bash
cd /home/intel/media_ai/edge-workloads-and-benchmarks/tss/ai_benchmark/cv_benchmark

# 提取当前benchmark结果
python3 extract_comprehensive_metrics.py benchmark_results_20260206_123327
```

## 输出文件

脚本会在benchmark目录下生成 `comprehensive_metrics.csv` 文件，包含所有提取的指标。

## 输出示例

```csv
模型,Batch Size,吞吐量(FPS),延迟-中位数(ms),延迟-平均(ms),延迟-最小(ms),延迟-最大(ms),峰值显存使用(MiB)
yolo11m-pose_fp32,1,277.85,14.35,14.38,7.21,19.49,242.76
yolo11m-pose_fp32,4,351.41,45.51,45.50,26.37,49.52,522.25
...
```

## 依赖要求

- Python 3.x
- 标准库: csv, re, pathlib, collections

## 目录结构要求

benchmark目录应包含：
- `*.log` 文件：包含性能指标的日志文件
- `*_bs*` 子目录：每个子目录包含 `gpu_metrics.csv` 文件

示例结构：
```
benchmark_results_20260206_123327/
├── yolo11m-pose_fp32.log
├── yolo11m-pose_fp32_bs1/
│   └── gpu_metrics.csv
├── yolo11m-pose_fp32_bs4/
│   └── gpu_metrics.csv
└── ...
```

## 脚本特性

1. **自动匹配**：根据目录名自动匹配模型和batch size
2. **效率计算**：自动计算FPS per GB效率指标
3. **数据汇总**：按模型分组显示结果
4. **错误处理**：对缺失或格式错误的文件有良好的容错性

## 输出报告示例

脚本运行后会显示：

```
综合性能和显存使用情况汇总
================================================================================

yolo11m-pose_fp32:
   BS         FPS      延迟-中位(ms)      延迟-平均(ms)       峰值显存(MB)     效率(FPS/GB)
  ---  ----------  -------------  -------------  -------------  -------------
    1      277.85          14.35          14.38         242.76       1172.02
    4      351.41          45.51          45.50         522.25        689.03
  ...
```

## 效率指标说明

**效率(FPS/GB)** = 吞吐量(FPS) / (峰值显存使用(MiB) / 1024)

该指标反映了模型在单位显存下的吞吐能力，数值越高表示显存利用效率越高。

## 显存数据说明

**峰值显存使用(MiB)** 是从 `gpu_metrics.csv` 文件中读取的 `GPU Memory Used (MiB)` 列的最大值，表示模型在推理过程中的显存峰值占用。该值是硬件选型和部署规划的重要依据。

## 常见问题

### Q: 显存数据显示为 0.00
A: 检查 gpu_metrics.csv 文件是否存在，以及是否包含 "GPU Memory Used" 列。

### Q: 性能数据提取失败
A: 确认日志文件包含 "Throughput" 和 "Latency" 相关信息。

### Q: 部分数据缺失
A: 脚本会继续处理可用数据，缺失的部分显示为 0 或跳过。
