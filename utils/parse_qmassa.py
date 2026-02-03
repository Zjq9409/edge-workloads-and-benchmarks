#!/usr/bin/env python3
"""Parse qmassa JSON output and extract metrics for CSV."""

import json
import sys

def parse_qmassa_json(json_file):
    """Extract latest metrics from qmassa JSON."""
    try:
        with open(json_file, 'r') as f:
            data = json.load(f)
        
        # Get the latest state (last item in states array)
        states = data.get('states', [])
        if not states:
            return None
        
        latest_state = states[-1]
        devs_state = latest_state.get('devs_state', [])
        
        if not devs_state:
            return None
        
        # Get first device stats
        dev = devs_state[0]
        dev_stats = dev.get('dev_stats', {})
        
        # Extract metrics
        metrics = {}
        
        # Power (average of latest samples)
        power_data = dev_stats.get('power', [])
        if power_data:
            latest_power = power_data[-1]
            metrics['gpu_power'] = latest_power.get('gpu_cur_power', 0)
        else:
            metrics['gpu_power'] = 0
        
        # Frequency (gt0 compute, gt1 media)
        freqs_data = dev_stats.get('freqs', [])
        if freqs_data and freqs_data[-1]:
            latest_freqs = freqs_data[-1]
            if len(latest_freqs) > 0:
                metrics['gpu_freq'] = latest_freqs[0].get('act_freq', 0)
            if len(latest_freqs) > 1:
                metrics['media_freq'] = latest_freqs[1].get('act_freq', 0)
        else:
            metrics['gpu_freq'] = 0
            metrics['media_freq'] = 0
        
        # Memory
        mem_info = dev_stats.get('mem_info', [])
        if mem_info:
            latest_mem = mem_info[-1]
            vram_used_bytes = latest_mem.get('vram_used', 0)
            metrics['mem_used'] = vram_used_bytes / (1024 * 1024)  # Convert to MiB
        else:
            metrics['mem_used'] = 0
        
        # Engine usage (average of latest samples)
        eng_usage = dev_stats.get('eng_usage', {})
        
        # VCS (video codec - decoder)
        vcs_usage = eng_usage.get('vcs', [])
        if vcs_usage:
            # qmassa may have multiple VCS engines, use first two
            metrics['decoder0'] = vcs_usage[0] if len(vcs_usage) > 0 else 0
            metrics['decoder1'] = vcs_usage[1] if len(vcs_usage) > 1 else 0
        else:
            metrics['decoder0'] = 0
            metrics['decoder1'] = 0
        
        # CCS (compute)
        ccs_usage = eng_usage.get('ccs', [])
        metrics['compute_util'] = ccs_usage[-1] if ccs_usage else 0
        
        # VECS (video enhancement)
        vecs_usage = eng_usage.get('vecs', [])
        if vecs_usage:
            metrics['media_enh0'] = vecs_usage[0] if len(vecs_usage) > 0 else 0
            metrics['media_enh1'] = vecs_usage[1] if len(vecs_usage) > 1 else 0
        else:
            metrics['media_enh0'] = 0
            metrics['media_enh1'] = 0
        
        # BCS (copy engine)
        bcs_usage = eng_usage.get('bcs', [])
        metrics['copy_eng'] = bcs_usage[-1] if bcs_usage else 0
        
        # RCS (render/encoder - approximation)
        rcs_usage = eng_usage.get('rcs', [])
        if rcs_usage:
            metrics['encoder0'] = rcs_usage[0] if len(rcs_usage) > 0 else 0
            metrics['encoder1'] = rcs_usage[1] if len(rcs_usage) > 1 else 0
        else:
            metrics['encoder0'] = 0
            metrics['encoder1'] = 0
        
        # GPU utilization (approximate from engine usage)
        all_engines = []
        for eng in [vcs_usage, ccs_usage, vecs_usage, bcs_usage, rcs_usage]:
            if eng:
                all_engines.extend([e for e in eng if isinstance(e, (int, float))])
        metrics['gpu_util'] = max(all_engines) if all_engines else 0
        
        # Temperatures (if available)
        temps = dev_stats.get('temps', [])
        metrics['gpu_temp'] = 0
        metrics['mem_temp'] = 0
        
        return metrics
        
    except Exception as e:
        print(f"Error parsing JSON: {e}", file=sys.stderr)
        return None

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: parse_qmassa.py <json_file>", file=sys.stderr)
        sys.exit(1)
    
    metrics = parse_qmassa_json(sys.argv[1])
    
    if metrics:
        # Output in CSV-friendly format
        print(f"{metrics['gpu_util']},{metrics['gpu_power']},{metrics['gpu_freq']},"
              f"{metrics['gpu_temp']},{metrics['mem_temp']},{metrics['mem_used']},"
              f"{metrics['compute_util']},{metrics['decoder0']},{metrics['decoder1']},"
              f"{metrics['encoder0']},{metrics['encoder1']},{metrics['copy_eng']},"
              f"{metrics['media_enh0']},{metrics['media_enh1']},{metrics['media_freq']}")
    else:
        # Return zeros if parsing fails
        print("0,0,0,0,0,0,0,0,0,0,0,0,0,0,0")
