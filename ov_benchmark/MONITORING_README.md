# GPU 监控功能使用说明

## 功能概述

脚本已集成 Intel XPU-SMI GPU 监控功能，可在模型测试期间实时采集 GPU 指标。
**所有模型的监控数据统一保存在一个 CSV 文件中，通过模型名和批次大小区分。**

## 监控指标

自动采集以下 8 个关键指标：

| ID | 指标 | 说明 | 单位 |
|----|------|------|------|
| 0  | GPU Utilization | GPU 整体利用率 | % |
| 1  | GPU Power | GPU 功耗 | W |
| 2  | GPU Frequency | GPU 频率 | MHz |
| 3  | GPU Core Temperature | GPU 核心温度 | °C |
| 4  | GPU Memory Temperature | 显存温度 | °C |
| 18 | GPU Memory Used | 显存使用量 | MiB |
| 22 | Compute Engine Util | 计算引擎利用率 | % |
| 24 | Media Decoder Util | 媒体解码器利用率 | % |

## 使用方法

### 启用监控

添加 `-M` 参数（需要 sudo 权限）：

```bash
# 测试单个模型
sudo ./run_model_benchmark.sh -M -m /home/intel/models/yolo11n.xml -d GPU.0 -b "1 4"

# 测试所有模型
sudo ./run_model_benchmark.sh -M -a -d GPU.0 -b "1 4 8"

# 自定义采样间隔（默认 1秒）
sudo ./run_model_benchmark.sh -M -I 2 -a -d GPU.0 -b "1 4"
```

## 输出文件

### 统一监控文件

**所有模型和批次的监控数据都保存在一个文件中：**

```
benchmark_results_<timestamp>/
├── all_models_monitor.csv   # ← 统一监控数据（包含所有模型）
├── yolo11n.log              # 性能测试日志
├── yolo11n-int8.log
├── yolov8n-seg.log
├── yolov8n-seg-int8.log
└── summary.txt              # 性能汇总
```

### 监控数据格式

**CSV 文件结构（每行对应一个时间点的采样）：**

| 列名 | 说明 | 示例 |
|------|------|------|
| Model Name | 模型名称 | yolo11n, yolo11n-int8 |
| Batch Size | 批次大小 | 1, 4, 8, 16 |
| Timestamp | 时间戳 | 2026-01-28 22:15:30 |
| GPU Utilization (%) | GPU利用率 | 85.5 |
| GPU Power (W) | 功耗 | 45.2 |
| GPU Frequency (MHz) | 频率 | 1200 |
| GPU Core Temp (°C) | 核心温度 | 65 |
| GPU Mem Temp (°C) | 显存温度 | 42 |
| GPU Memory Used (MiB) | 显存使用 | 8192 |
| Compute Engine Util (%) | 计算引擎利用率 | 90.2 |
| Media Decoder Util (%) | 解码器利用率 | 75.3 |

**CSV示例：**
```csv
Model Name,Batch Size,Timestamp,GPU Utilization (%),GPU Power (W),...
yolo11n,1,2026-01-28 22:10:00,75.2,38.5,1150,58,38,6144,82.1,0.0
yolo11n,1,2026-01-28 22:10:01,76.8,39.2,1180,59,39,6144,83.5,0.0
yolo11n,4,2026-01-28 22:11:00,92.3,52.8,1300,68,45,8192,95.6,0.0
yolo11n-int8,1,2026-01-28 22:12:00,68.5,32.1,1100,54,36,5120,75.2,0.0
```

## 完整示例

```bash
# 测试所有模型，启用监控，每2秒采样
cd /home/intel/media_ai/edge-workloads-and-benchmarks/ov_benchmark
sudo ./run_model_benchmark.sh -M -a -d GPU.0 -I 2 -b "1 4 8"

# 查看统一监控数据（前20行）
head -20 benchmark_results_*/all_models_monitor.csv

# 查看特定模型的监控数据
grep "yolo11n," benchmark_results_*/all_models_monitor.csv | head -10

# 查看特定batch size的监控数据
grep ",8," benchmark_results_*/all_models_monitor.csv | head -10
```

## 数据分析示例

### Python 数据分析

```python
import pandas as pd
import matplotlib.pyplot as plt

# 读取统一监控数据
df = pd.read_csv('all_models_monitor.csv')

# 按模型分组分析平均功耗
power_by_model = df.groupby(['Model Name', 'Batch Size'])['GPU Power (W)'].mean()
print(power_by_model)

# 绘制各模型各batch的功耗对比
fig, ax = plt.subplots(figsize=(14, 6))
for model in df['Model Name'].unique():
    model_data = df[df['Model Name'] == model]
    for bs in sorted(model_data['Batch Size'].unique()):
        bs_data = model_data[model_data['Batch Size'] == bs]
        ax.plot(range(len(bs_data)), bs_data['GPU Power (W)'], 
                label=f'{model} (BS={bs})')

ax.set_xlabel('Sample Index')
ax.set_ylabel('Power (W)')
ax.set_title('GPU Power Consumption - All Models & Batch Sizes')
ax.legend()
plt.savefig('power_comparison.png', dpi=150)

# 温度分析
temp_stats = df.groupby(['Model Name', 'Batch Size'])['GPU Core Temp (°C)'].agg(['mean', 'max'])
print("\n温度统计：")
print(temp_stats)
```

### Bash 快速统计

```bash
cd benchmark_results_<timestamp>

# 统计各模型采样数量
cut -d',' -f1 all_models_monitor.csv | sort | uniq -c

# 查看最高功耗记录
sort -t',' -k5 -nr all_models_monitor.csv | head -5

# 计算yolo11n batch=8的平均GPU利用率
awk -F',' '$1=="yolo11n" && $2==8 {sum+=$4; count++} END {print sum/count}' all_models_monitor.csv
```

## 监控工作原理

1. **初始化**：脚本启动时创建 `all_models_monitor.csv` 并写入表头
2. **独立监控**：每个模型的每个batch size测试时，启动独立的xpu-smi进程
3. **实时合并**：batch测试完成后，自动将数据追加到统一CSV，添加模型名和batch size列
4. **自动清理**：临时的单batch监控文件会被自动删除

## 注意事项

1. **需要 sudo 权限**：xpu-smi 需要 root 权限访问 GPU 传感器
2. **自动清理**：每个batch的监控进程会在测试结束后自动停止
3. **数据完整性**：所有模型数据在一个CSV中，便于对比分析
4. **区分标识**：通过 Model Name 和 Batch Size 两列区分不同测试
5. **采样精度**：默认1秒间隔，可通过 `-I` 参数调整（建议1-5秒）

## 帮助信息

```bash
./run_model_benchmark.sh -h
```
