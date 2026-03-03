import time
import requests
import json
import sys
import argparse
import os
import numpy as np

# 终端色彩
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

def run_vlm_benchmark(args):
    url = f"http://{args.host}:{args.port}/v1/chat/completions"
    
    stats = {
        "ttft": [],
        "tpot": [],
        "total_time": [],
        "token_counts": [],
        "throughput": []
    }

    print(f"\n{Colors.BOLD}{Colors.OKBLUE}>>> 启动 VLM 性能测试程序 {Colors.ENDC}")
    print(f"{Colors.OKCYAN}模型: {args.model}")
    print(f"参数: {args.rounds} 轮次 | Max Tokens: {args.max_tokens} | Host: {args.host}:{args.port}{Colors.ENDC}\n")

    for i in range(args.rounds):
        print(f"{Colors.HEADER}[轮次 {i+1:02d}/{args.rounds:02d}]{Colors.ENDC}", end=" ", flush=True)
        
        # 根据输入文件格式动态调整type
        input_lower = args.input.lower()
        if input_lower.endswith('.jpg') or input_lower.endswith('.jpeg'):
            media_type = "image_url"
        elif input_lower.endswith('.mp4'):
            media_type = "video_url"
        else:
            media_type = "image_url"  # 默认仍为image_url

        payload = {
            "model": args.model,
            "messages": [{"role": "user", "content": [
                {"type": "text", "text": args.prompt},
                {"type": media_type, media_type: {"url": args.input}},
                # {"fps": 1} if media_type == "video_url" else {}
            ]}],
            "max_tokens": args.max_tokens,
            "stream": True,
            "stream_options": {"include_usage": True}
        }

        start_time = time.perf_counter()
        ttft = None
        first_token_time = 0
        tokens_timestamps = []
        total_tokens = 0

        try:
            response = requests.post(url, json=payload, stream=True, timeout=args.timeout)
            response.raise_for_status()
            
            for line in response.iter_lines():
                if line:
                    line_data = line.decode('utf-8')
                    if line_data.startswith("data: "):
                        data_str = line_data[6:]
                        if data_str == "[DONE]": break
                        
                        chunk = json.loads(data_str)
                        if "usage" in chunk and chunk["usage"] is not None:
                            total_tokens = chunk["usage"]["completion_tokens"]
                            continue

                        content = chunk['choices'][0]['delta'].get('content', '')
                        if content:
                            if ttft is None:
                                first_token_time = time.perf_counter()
                                ttft = first_token_time - start_time
                            else:
                                tokens_timestamps.append(time.perf_counter())
                            if total_tokens == 0: total_tokens += 1 
            
            end_time = time.perf_counter()
            
            # 核心性能计算
            total_duration = end_time - start_time
            generation_duration = end_time - first_token_time
            
            current_tpot = generation_duration / total_tokens if total_tokens > 1 else 0
            current_throughput = total_tokens / generation_duration if generation_duration > 0 else 0
            
            stats["ttft"].append(ttft)
            stats["tpot"].append(current_tpot)
            stats["total_time"].append(total_duration)
            stats["token_counts"].append(total_tokens)
            stats["throughput"].append(current_throughput)
            
            print(f"✅ 完成 | TTFT: {ttft:.3f}s | TPS: {current_throughput:.2f} tok/s")

        except Exception as e:
            print(f"❌ {Colors.FAIL}错误: {e}{Colors.ENDC}")

    # --- 最终性能报告输出 ---
    print(f"\n{Colors.OKGREEN}{'='*65}{Colors.ENDC}")
    print(f"{Colors.BOLD}📊 Intel Arc GPU 性能测试报告汇总{Colors.ENDC}")
    print(f"{Colors.OKGREEN}{'-'*65}{Colors.ENDC}")
    
    row_fmt = "{:<28} {:<18} {:<15}"
    print(row_fmt.format("Metric", "Average", "Std Dev"))
    print(f"{'-'*65}")
    
    results_list = [
        ("TTFT (Prefill Latency)", "ttft", "s"),
        ("TPOT (Decode Latency)", "tpot", "ms"),
        ("Throughput (Generation)", "throughput", "tokens/s"),
        ("Total Latency (End-to-End)", "total_time", "s"),
        ("Tokens per Request", "token_counts", "tokens")
    ]

    for label, key, unit in results_list:
        avg_val = np.mean(stats[key])
        std_val = np.std(stats[key])
        
        if key == "tpot":
            print(row_fmt.format(label, f"{avg_val*1000:.2f} ms", f"{std_val*1000:.2f} ms"))
        elif key == "throughput":
            print(row_fmt.format(label, f"{Colors.BOLD}{avg_val:.2f} {unit}{Colors.ENDC}", f"{std_val:.2f}"))
        else:
            print(row_fmt.format(label, f"{avg_val:.3f} {unit}", f"{std_val:.3f}"))

    print(f"{Colors.OKGREEN}{'='*65}{Colors.ENDC}\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="VLM API 性能基准测试工具 (vLLM/OpenAI 兼容)")
    
    # 模型与路径参数
    parser.add_argument("-m", "--model", type=str, default="Qwen2.5-VL-7B-Instruct", help="模型名称")
    parser.add_argument("-i", "--input", type=str, required=True, help="测试图片/视频的 URL 或本地路径 (file:/llm/models/test/test.jpg)")
    parser.add_argument("-p", "--prompt", type=str, default="What is this", help="推理提示词")
    
    # 测试配置参数
    parser.add_argument("-n", "--rounds", type=int, default=5, help="测试执行轮次")
    parser.add_argument("-mt", "--max-tokens", type=int, default=128, help="最大生成 token 数")
    
    # 网络配置参数
    parser.add_argument("--host", type=str, default="localhost", help="API 服务地址")
    parser.add_argument("--port", type=int, default=8000, help="API 服务端口")
    parser.add_argument("--timeout", type=int, default=120, help="请求超时时间(秒)")

    args = parser.parse_args()
    
    run_vlm_benchmark(args)