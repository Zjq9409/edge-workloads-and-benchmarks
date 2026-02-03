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
    
    # Dynamically detect available metrics from CSV columns
    available_columns = df.columns.tolist()
    
    # Define base metrics to plot (will filter based on availability)
    base_metrics = [
        'GPU Utilization (%)',
        'GPU Power (W)',
        'GPU Frequency (MHz)',
        'GPU Core Temperature (Celsius Degree)',
        'GPU Memory Used (MiB)',
        'Decoder Engine 0 (%)',
        'Decoder Engine 1 (%)',
        'Media Engine Frequency (MHz)',
    ]
    
    # Build metrics dict with available metrics
    metrics = {}
    for metric in base_metrics:
        if metric in available_columns:
            # Check Frequency first before Engine (to avoid misclassifying "Media Engine Frequency")
            if 'Frequency' in metric:
                metrics[metric] = {'ylabel': 'Frequency (MHz)', 'ylim': None}
            elif 'Power' in metric:
                metrics[metric] = {'ylabel': 'Power (W)', 'ylim': None}
            elif 'Temperature' in metric or 'Temp' in metric:
                metrics[metric] = {'ylabel': 'Temperature (°C)', 'ylim': None}
            elif 'Memory' in metric:
                metrics[metric] = {'ylabel': 'Memory (MiB)', 'ylim': None}
            elif 'Utilization' in metric or 'Engine' in metric:
                metrics[metric] = {'ylabel': 'Utilization (%)', 'ylim': [0, 100]}
            else:
                metrics[metric] = {'ylabel': '', 'ylim': None}
    
    # Dynamically build engine metrics from available columns
    engine_metrics = {}
    
    # Pattern to match engine columns
    engine_patterns = [
        'Compute Engine',
        'Decoder Engine',
        'Encoder Engine',
        'Copy Engine',
        'Media Enhancement Engine',
        'Media Engine Frequency'
    ]
    
    for col in available_columns:
        if any(pattern in col for pattern in engine_patterns):
            if 'Frequency' in col:
                engine_metrics[col] = {'ylabel': 'Frequency (MHz)', 'ylim': None}
            else:
                engine_metrics[col] = {'ylabel': 'Utilization (%)', 'ylim': [0, 100]}
    
    # Plot 1: Main GPU Metrics (dynamic grid based on number of metrics)
    num_main_metrics = len(metrics)
    if num_main_metrics > 0:
        ncols = 4
        nrows = (num_main_metrics + ncols - 1) // ncols  # Ceiling division
        fig1, axes1 = plt.subplots(nrows, ncols, figsize=(20, 5*nrows))
        fig1.suptitle(f'GPU Metrics Overview - {model_name} (Batch Size: {batch_size})', fontsize=16, fontweight='bold')
        
        if nrows == 1 and ncols == 1:
            axes1_flat = [axes1]
        elif nrows == 1 or ncols == 1:
            axes1_flat = axes1.flatten()
        else:
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
        
        # Hide unused subplots
        for idx in range(num_main_metrics, len(axes1_flat)):
            axes1_flat[idx].axis('off')
        
        plt.tight_layout()
        output_file1 = os.path.join(output_dir, 'gpu_metrics_main.png')
        plt.savefig(output_file1, dpi=150, bbox_inches='tight')
        plt.close(fig1)
        print(f"Saved main metrics plot to {output_file1}")
    else:
        print("No main metrics available to plot")
    
    # Plot 2: Engine Utilization (dynamic grid based on number of engines)
    num_engine_metrics = len(engine_metrics)
    if num_engine_metrics > 0:
        ncols = 2
        nrows = (num_engine_metrics + ncols - 1) // ncols  # Ceiling division
        fig2, axes2 = plt.subplots(nrows, ncols, figsize=(16, 4*nrows))
        fig2.suptitle(f'GPU Engine Utilization - {model_name} (Batch Size: {batch_size})', fontsize=16, fontweight='bold')
        
        if nrows == 1 and ncols == 1:
            axes2_flat = [axes2]
        elif nrows == 1 or ncols == 1:
            axes2_flat = axes2.flatten()
        else:
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
                
                if 'Frequency' in metric:
                    stats_text = f'Avg: {mean_val:.0f}\nMax: {max_val:.0f}'
                else:
                    stats_text = f'Avg: {mean_val:.2f}%\nMax: {max_val:.2f}%'
                ax.text(0.02, 0.98, stats_text, transform=ax.transAxes,
                       verticalalignment='top', bbox=dict(boxstyle='round', facecolor='lightblue', alpha=0.5),
                       fontsize=8)
        
        # Hide unused subplots
        for idx in range(num_engine_metrics, len(axes2_flat)):
            axes2_flat[idx].axis('off')
        
        plt.tight_layout()
        output_file2 = os.path.join(output_dir, 'gpu_metrics_engines.png')
        plt.savefig(output_file2, dpi=150, bbox_inches='tight')
        plt.close(fig2)
        print(f"Saved engine metrics plot to {output_file2}")
    else:
        print("No engine metrics available to plot")
    
    # Print summary statistics
    print("\n" + "="*60)
    print("GPU Metrics Summary")
    print("="*60)
    print(f"Model: {model_name}")
    print(f"Batch Size: {batch_size}")
    print(f"Total Samples: {len(df)}")
    print("-"*60)
    
    # Print statistics for key metrics (those that exist)
    key_metrics = [
        'GPU Utilization (%)',
        'GPU Power (W)',
        'GPU Core Temperature (Celsius Degree)',
        'GPU Memory Temperature (Celsius Degree)',
        'GPU Memory Used (MiB)'
    ]
    
    for metric in key_metrics:
        if metric in df.columns:
            data = pd.to_numeric(df[metric], errors='coerce')
            print(f"{metric:45s}: Avg={data.mean():7.2f}, Max={data.max():7.2f}, Min={data.min():7.2f}")
    
    # Print all compute engines
    for col in sorted(available_columns):
        if 'Compute Engine' in col and col not in key_metrics:
            data = pd.to_numeric(df[col], errors='coerce')
            print(f"{col:45s}: Avg={data.mean():7.2f}, Max={data.max():7.2f}, Min={data.min():7.2f}")
    
    # Print decoder engines
    for col in sorted(available_columns):
        if 'Decoder Engine' in col:
            data = pd.to_numeric(df[col], errors='coerce')
            print(f"{col:45s}: Avg={data.mean():7.2f}, Max={data.max():7.2f}, Min={data.min():7.2f}")
    
    # Print encoder engines
    for col in sorted(available_columns):
        if 'Encoder Engine' in col:
            data = pd.to_numeric(df[col], errors='coerce')
            print(f"{col:45s}: Avg={data.mean():7.2f}, Max={data.max():7.2f}, Min={data.min():7.2f}")
    
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
