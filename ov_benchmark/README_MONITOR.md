# GPU 监控脚本使用说明

## 文件说明

### gpu_monitor.sh
独立的GPU监控脚本，可以被其他测试脚本复用。

**功能：**
- 使用 xpu-smi 采集 GPU 指标
- 直接写入统一的 CSV 文件
- 每行数据包含模型名、批次大小、时间戳和GPU指标

**使用方法：**
```bash
sudo ./gpu_monitor.sh <output_csv> <device_id> [interval] [model_name] [batch_size]
```

**参数：**
- `output_csv`: 输出CSV文件路径
- `device_id`: GPU设备ID (0, 1, ...)
- `interval`: 采样间隔（秒），默认1
- `model_name`: 模型名称，用于标识
- `batch_size`: 批次大小，用于标识

**示例：**
```bash
# 监控GPU 0，每秒采样，标记为yolo11n模型，批次大小4
sudo ./gpu_monitor.sh /tmp/monitor.csv 0 1 yolo11n 4 &
MONITOR_PID=$!

# ... 运行测试 ...

# 停止监控
sudo kill $MONITOR_PID
```

## 采集的指标

| ID | 指标 | 说明 |
|----|------|------|
| 0 | GPU Utilization (%) | GPU整体利用率 |
| 1 | GPU Power (W) | GPU功耗 |
| 2 | GPU Frequency (MHz) | GPU频率 |
| 3 | GPU Core Temperature (°C) | GPU核心温度 |
| 4 | GPU Memory Temperature (°C) | 显存温度 |
| 18 | GPU Memory Used (MiB) | 显存使用量 |
| 22 | Compute Engine Util (%) | 计算引擎利用率 |
| 24 | Media Decoder Util (%) | 媒体解码器利用率 |

## CSV 输出格式

```csv
Model Name,Batch Size,Timestamp,DeviceId,GPU Utilization (%),GPU Power (W),GPU Frequency (MHz),GPU Core Temp (°C),GPU Mem Temp (°C),GPU Memory Used (MiB),Compute Engine Util (%),Media Decoder Util (%)
yolo11n,4,2026-01-29 10:30:00,0,85.5,45.2,1200,65,42,8192,90.2,75.3
yolo11n,4,2026-01-29 10:30:01,0,86.1,45.8,1210,66,43,8192,91.0,76.1
```

## 集成到其他测试脚本

```bash
#!/bin/bash

# 1. 定义输出文件
MONITOR_CSV="./results/gpu_monitor.csv"

# 2. 启动监控
sudo ./gpu_monitor.sh "$MONITOR_CSV" 0 1 "my_model" 8 &
MONITOR_PID=$!

# 3. 运行你的测试
# ... your test code ...

# 4. 停止监控
sudo kill $MONITOR_PID
sleep 1  # 等待最后的数据写入
```

## 系统信息收集

run_model_benchmark.sh 现在会在每个日志文件中自动记录：
- 操作系统信息
- 内核版本
- CPU型号和核心数
- 内存总量和可用量
- GPU设备信息

## 注意事项

1. 需要sudo权限运行监控脚本
2. 确保xpu-smi已正确安装
3. 监控进程会持续运行直到被kill
4. CSV文件会自动创建表头（如果不存在）
5. 数据会追加到同一个CSV文件，方便对比不同测试
