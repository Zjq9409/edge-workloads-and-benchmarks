#!/usr/bin/env python3
"""
综合性能和显存指标提取脚本
从日志文件和gpu_metrics.csv中提取所有指标
"""

import os
import re
import csv
from pathlib import Path
from collections import defaultdict

def parse_log_file(log_file):
    """解析日志文件提取性能数据"""
    data = []
    model_name = None
    current_bs = None
    current_metrics = {}
    
    with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
    
    # 提取模型名称
    match = re.search(r'Model Benchmark:\s+(\S+)', content)
    if match:
        model_name = match.group(1)
    
    # 提取每个batch size的数据块
    batch_blocks = re.split(r'={40,}\nBatch Size:\s+(\d+)\n={40,}', content)
    
    for i in range(1, len(batch_blocks), 2):
        bs = int(batch_blocks[i])
        block = batch_blocks[i + 1]
        
        # 提取性能指标
        throughput_match = re.search(r'Throughput:\s+([\d.]+)\s+FPS', block)
        median_match = re.search(r'Median:\s+([\d.]+)\s+ms', block)
        average_match = re.search(r'Average:\s+([\d.]+)\s+ms', block)
        min_match = re.search(r'Min:\s+([\d.]+)\s+ms', block)
        max_match = re.search(r'Max:\s+([\d.]+)\s+ms', block)
        
        if throughput_match and median_match:
            data.append({
                'model': model_name,
                'batch_size': bs,
                'fps': float(throughput_match.group(1)),
                'latency_median': float(median_match.group(1)),
                'latency_avg': float(average_match.group(1)) if average_match else 0.0,
                'latency_min': float(min_match.group(1)) if min_match else 0.0,
                'latency_max': float(max_match.group(1)) if max_match else 0.0
            })
    
    return data

def extract_vram_from_gpu_metrics(csv_file):
    """从gpu_metrics.csv提取显存使用情况"""
    vram_values = []
    
    try:
        with open(csv_file, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                # 处理可能的列名变体，注意列名可能有空格
                vram = None
                for key in row.keys():
                    key_lower = key.strip().lower()
                    if 'memory used' in key_lower or 'vram' in key_lower:
                        try:
                            vram = float(row[key].strip())
                            vram_values.append(vram)
                        except (ValueError, AttributeError):
                            pass
                        break
    except Exception as e:
        print(f"  ⚠ Error reading {csv_file}: {e}")
        return None
    
    if not vram_values:
        return None
    
    # 直接取峰值显存（稳定运行时的显存使用）
    peak_vram = max(vram_values)
    
    return {
        'peak': peak_vram,
        'min': min(vram_values),
        'avg': peak_vram  # 直接使用峰值，不计算平均
    }

def process_benchmark_directory(benchmark_dir):
    """处理benchmark目录，提取所有数据"""
    benchmark_dir = Path(benchmark_dir)
    
    # 收集性能数据
    performance_data = {}
    for log_file in benchmark_dir.glob('*.log'):
        print(f"Processing log: {log_file.name}")
        log_data = parse_log_file(log_file)
        for item in log_data:
            key = (item['model'], item['batch_size'])
            performance_data[key] = item
    
    # 收集显存数据
    vram_data = {}
    for subdir in benchmark_dir.iterdir():
        if subdir.is_dir():
            gpu_metrics_file = subdir / 'gpu_metrics.csv'
            if gpu_metrics_file.exists():
                # 从目录名提取模型和batch size
                dir_name = subdir.name
                match = re.match(r'(.+)_bs(\d+)', dir_name)
                if match:
                    model = match.group(1)
                    bs = int(match.group(2))
                    
                    vram = extract_vram_from_gpu_metrics(gpu_metrics_file)
                    if vram:
                        vram_data[(model, bs)] = vram
    
    print(f"\nFound {len(performance_data)} performance records")
    print(f"Found {len(vram_data)} VRAM records")
    
    return performance_data, vram_data

def merge_data(performance_data, vram_data):
    """合并性能和显存数据"""
    merged = []
    
    for key, perf in sorted(performance_data.items()):
        model, bs = key
        vram = vram_data.get(key, {'peak': 0.0, 'min': 0.0})
        
        merged.append({
            '模型': model,
            'Batch Size': bs,
            '吞吐量(FPS)': perf['fps'],
            '延迟-中位数(ms)': perf['latency_median'],
            '延迟-平均(ms)': perf['latency_avg'],
            '延迟-最小(ms)': perf['latency_min'],
            '延迟-最大(ms)': perf['latency_max'],
            '峰值显存使用(MiB)': vram['peak']
        })
    
    return merged

def save_to_csv(data, output_file):
    """保存到CSV文件"""
    if not data:
        print("No data to save!")
        return
    
    fieldnames = [
        '模型', 'Batch Size', '吞吐量(FPS)', 
        '延迟-中位数(ms)', '延迟-平均(ms)', '延迟-最小(ms)', '延迟-最大(ms)',
        '峰值显存使用(MiB)'
    ]
    
    with open(output_file, 'w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in data:
            writer.writerow(row)
    
    print(f"\n✓ Saved to: {output_file}")

def print_summary_table(data):
    """打印汇总表格"""
    if not data:
        return
    
    print("\n" + "="*130)
    print("综合性能和显存使用情况汇总")
    print("="*130)
    
    current_model = None
    for item in data:
        if item['模型'] != current_model:
            current_model = item['模型']
            print(f"\n{current_model}:")
            print(f"  {'BS':>3}  {'FPS':>10}  {'延迟-中位(ms)':>13}  {'延迟-平均(ms)':>13}  {'峰值显存(MB)':>13}  {'效率(FPS/GB)':>13}")
            print(f"  {'-'*3}  {'-'*10}  {'-'*13}  {'-'*13}  {'-'*13}  {'-'*13}")
        
        bs = item['Batch Size']
        fps = item['吞吐量(FPS)']
        lat_med = item['延迟-中位数(ms)']
        lat_avg = item['延迟-平均(ms)']
        vram_used = item['峰值显存使用(MiB)']
        
        # 计算效率（FPS per GB）
        efficiency = fps / (vram_used / 1024.0) if vram_used > 0 else 0
        
        print(f"  {bs:>3}  {fps:>10.2f}  {lat_med:>13.2f}  {lat_avg:>13.2f}  "
              f"{vram_used:>13.2f}  {efficiency:>13.2f}")

def main():
    import sys
    
    if len(sys.argv) > 1:
        benchmark_dir = sys.argv[1]
    else:
        benchmark_dir = '/home/intel/media_ai/edge-workloads-and-benchmarks/tss/ai_benchmark/cv_benchmark/benchmark_results_20260206_123327'
    
    benchmark_dir = Path(benchmark_dir)
    
    if not benchmark_dir.exists():
        print(f"❌ Directory not found: {benchmark_dir}")
        return 1
    
    print(f"Processing: {benchmark_dir}")
    print("="*80)
    
    # 提取数据
    performance_data, vram_data = process_benchmark_directory(benchmark_dir)
    
    # 合并数据
    merged_data = merge_data(performance_data, vram_data)
    
    # 保存CSV
    output_file = benchmark_dir / 'comprehensive_metrics.csv'
    save_to_csv(merged_data, output_file)
    
    # 打印汇总表格
    print_summary_table(merged_data)
    
    print(f"\n{'='*130}")
    print(f"总计: {len(set(item['模型'] for item in merged_data))} 个模型, {len(merged_data)} 个配置")
    print("="*130)
    
    return 0

if __name__ == '__main__':
    import sys
    sys.exit(main())
