#!/usr/bin/env python3

"""
GPU Metrics Plotting Script
Usage: python3 plot_gpu_metrics.py <gpu_monitor.csv> [output_dir]
"""

import sys
import os
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from datetime import datetime

def plot_gpu_metrics(csv_file, output_dir=None):
    """
    Plot GPU monitoring metrics from CSV file
    
    Args:
        csv_file: Path to gpu_monitor.csv file
        output_dir: Directory to save plots (default: same as CSV file)
    """
    
    # Read CSV file
    try:
        df = pd.read_csv(csv_file, skipinitialspace=True)
        print(f"Loaded {len(df)} data points from {csv_file}")
    except Exception as e:
        print(f"Error reading CSV file: {e}")
        return
    
    # Set output directory
    if output_dir is None:
        output_dir = os.path.dirname(csv_file)
    os.makedirs(output_dir, exist_ok=True)
    
    # Parse timestamp
    use_time_axis = False
    if 'Timestamp' in df.columns:
        # Try different timestamp formats
        try:
            # Try full datetime format first
            df['Time'] = pd.to_datetime(df['Timestamp'], format='%Y-%m-%d %H:%M:%S')
            use_time_axis = True
        except:
            try:
                # Try time only format (HH:MM:SS.fff)
                df['Time'] = pd.to_datetime(df['Timestamp'], format='%H:%M:%S.%f')
                use_time_axis = True
            except:
                try:
                    # Generic parsing
                    df['Time'] = pd.to_datetime(df['Timestamp'], errors='coerce')
                    if not df['Time'].isna().all():
                        use_time_axis = True
                    else:
                        print("Warning: Could not parse timestamps, using sample index instead")
                        df['Time'] = range(len(df))
                except:
                    print("Warning: Timestamp parsing failed, using sample index instead")
                    df['Time'] = range(len(df))
    else:
        df['Time'] = range(len(df))
    
    # Calculate relative time in seconds from start for better plotting
    if use_time_axis and isinstance(df['Time'].iloc[0], pd.Timestamp):
        df['Time_seconds'] = (df['Time'] - df['Time'].iloc[0]).dt.total_seconds()
        x_axis_data = df['Time_seconds']
        x_label = 'Time (seconds from start)'
    else:
        x_axis_data = df.index
        x_label = 'Sample Index'
    
    # Get model info for title
    model_name = df['Model Name'].iloc[0] if 'Model Name' in df.columns else 'Unknown'
    batch_size = df['Batch Size'].iloc[0] if 'Batch Size' in df.columns else 'N/A'
    
    # Define metrics to plot
    metrics = {
        'Compute Engine Util (%)': {'ylabel': 'Utilization (%)', 'ylim': [0, 100]},
        'GPU Power (W)': {'ylabel': 'Power (W)', 'ylim': None},
        'GPU Frequency (MHz)': {'ylabel': 'Frequency (MHz)', 'ylim': None},
        'GPU Core Temp (°C)': {'ylabel': 'Temperature (°C)', 'ylim': None},
        'Decoder Engine 0 (%)': {'ylabel': 'Utilization (%)', 'ylim': [0, 100]},
        'Decoder Engine 1 (%)': {'ylabel': 'Utilization (%)', 'ylim': [0, 100]},
        'GPU Memory Used (MiB)': {'ylabel': 'Memory (MiB)', 'ylim': None},
        'Media Engine Frequency (MHz)': {'ylabel': 'Frequency (MHz)', 'ylim': None},
    }
    
    engine_metrics = {
        'GPU Utilization (%)': {'ylabel': 'Utilization (%)', 'ylim': [0, 100]},
        'Compute Engine Util (%)': {'ylabel': 'Utilization (%)', 'ylim': [0, 100]},
        'Decoder Engine 0 (%)': {'ylabel': 'Utilization (%)', 'ylim': [0, 100]},
        'Decoder Engine 1 (%)': {'ylabel': 'Utilization (%)', 'ylim': [0, 100]},
        'Encoder Engine 0 (%)': {'ylabel': 'Utilization (%)', 'ylim': [0, 100]},
        'Encoder Engine 1 (%)': {'ylabel': 'Utilization (%)', 'ylim': [0, 100]},
        'Copy Engine 0 (%)': {'ylabel': 'Utilization (%)', 'ylim': [0, 100]},
        'Media Enhancement Engine 0 (%)': {'ylabel': 'Utilization (%)', 'ylim': [0, 100]},
        'Media Enhancement Engine 1 (%)': {'ylabel': 'Utilization (%)', 'ylim': [0, 100]},
        'Media Engine Frequency (MHz)': {'ylabel': 'Frequency (MHz)', 'ylim': None},
    }
    
    # Plot 1: Main GPU Metrics (2x4 grid for 7 metrics)
    fig1, axes1 = plt.subplots(2, 4, figsize=(20, 10))
    fig1.suptitle(f'GPU Metrics Overview - {model_name} (Batch Size: {batch_size})', fontsize=16, fontweight='bold')
    
    axes1_flat = axes1.flatten()
    for idx, (metric, config) in enumerate(metrics.items()):
        ax = axes1_flat[idx]
        if metric in df.columns:
            # Convert to numeric, replacing any non-numeric values with NaN
            data = pd.to_numeric(df[metric], errors='coerce')
            ax.plot(x_axis_data, data, linewidth=1.5, color='#2E86AB', marker='o', markersize=3)
            ax.set_xlabel(x_label)
            ax.set_ylabel(config['ylabel'])
            ax.set_title(metric, fontweight='bold')
            ax.grid(True, alpha=0.3)
            
            if config['ylim']:
                ax.set_ylim(config['ylim'])
            
            # Add statistics
            mean_val = data.mean()
            max_val = data.max()
            min_val = data.min()
            
            stats_text = f'Avg: {mean_val:.2f}\nMax: {max_val:.2f}\nMin: {min_val:.2f}'
            ax.text(0.02, 0.98, stats_text, transform=ax.transAxes,
                   verticalalignment='top', bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5),
                   fontsize=8)
        else:
            ax.text(0.5, 0.5, f'{metric}\nNot Available', ha='center', va='center')
            ax.set_title(metric, fontweight='bold')
    
    plt.tight_layout()
    output_file1 = os.path.join(output_dir, 'gpu_metrics_main.png')
    plt.savefig(output_file1, dpi=150, bbox_inches='tight')
    print(f"Saved main metrics plot to {output_file1}")
    
    # Plot 2: Engine Utilization (5x2 grid for 9 metrics)
    fig2, axes2 = plt.subplots(5, 2, figsize=(16, 20))
    fig2.suptitle(f'GPU Engine Utilization - {model_name} (Batch Size: {batch_size})', fontsize=16, fontweight='bold')
    
    axes2_flat = axes2.flatten()
    for idx, (metric, config) in enumerate(engine_metrics.items()):
        ax = axes2_flat[idx]
        if metric in df.columns:
            data = pd.to_numeric(df[metric], errors='coerce')
            ax.plot(x_axis_data, data, linewidth=1.5, color='#A23B72', marker='o', markersize=3)
            ax.set_xlabel(x_label)
            ax.set_ylabel(config['ylabel'])
            ax.set_title(metric, fontweight='bold')
            ax.grid(True, alpha=0.3)
            
            if config['ylim']:
                ax.set_ylim(config['ylim'])
            
            # Add statistics
            mean_val = data.mean()
            max_val = data.max()
            
            stats_text = f'Avg: {mean_val:.2f}%\nMax: {max_val:.2f}%'
            ax.text(0.02, 0.98, stats_text, transform=ax.transAxes,
                   verticalalignment='top', bbox=dict(boxstyle='round', facecolor='lightblue', alpha=0.5),
                   fontsize=8)
        else:
            ax.text(0.5, 0.5, f'{metric}\nNot Available', ha='center', va='center')
            ax.set_title(metric, fontweight='bold')
    
    plt.tight_layout()
    output_file2 = os.path.join(output_dir, 'gpu_metrics_engines.png')
    plt.savefig(output_file2, dpi=150, bbox_inches='tight')
    print(f"Saved engine metrics plot to {output_file2}")
    
    # Print summary statistics
    print("\n" + "="*60)
    print("GPU Metrics Summary")
    print("="*60)
    print(f"Model: {model_name}")
    print(f"Batch Size: {batch_size}")
    print(f"Total Samples: {len(df)}")
    print("-"*60)
    
    for metric in ['GPU Utilization (%)', 'GPU Power (W)', 'GPU Core Temp (°C)', 
                   'GPU Memory Used (MiB)', 'Compute Engine Util (%)', 'Decoder Engine 0 (%)', 'Decoder Engine 1 (%)']:
        if metric in df.columns:
            data = pd.to_numeric(df[metric], errors='coerce')
            print(f"{metric:35s}: Avg={data.mean():7.2f}, Max={data.max():7.2f}, Min={data.min():7.2f}")
    
    print("="*60)
    print(f"\nPlots saved to: {output_dir}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 plot_gpu_metrics.py <gpu_monitor.csv> [output_dir]")
        print("\nExample:")
        print("  python3 plot_gpu_metrics.py ./benchmark_results/gpu_monitor.csv")
        print("  python3 plot_gpu_metrics.py ./benchmark_results/gpu_monitor.csv ./plots")
        sys.exit(1)
    
    csv_file = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else None
    
    if not os.path.exists(csv_file):
        print(f"Error: CSV file not found: {csv_file}")
        sys.exit(1)
    
    plot_gpu_metrics(csv_file, output_dir)
    print("\nDone!")

if __name__ == '__main__':
    main()
