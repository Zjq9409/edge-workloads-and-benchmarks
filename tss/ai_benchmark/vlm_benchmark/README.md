# OpenVINO VLM Model Benchmark

Benchmark OpenVINO VLM models using Intel's OpenVINI genai package.

## Overview

This benchmark tests OpenVINO VLM model inference performance

## Usage

```
python3 benchmark_vlm.py [OPTIONS]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-m <model>` | Model path<br>Example: /home/intel/models/Qwen2.5-VL-3B-Instruct | required |
| `-p <prompt>` | Prompt input | if not fill, default is 'What is on the image?' |
| `-pf <prompt file>` | Prompt file | profile file path |
| `-i <image>` | Image input | image file path |
| `-d <device>` | GPU device: GPU.0, GPU.1 | GPU.0 |
| `-nw <num warmup>` | Num of warm-up iteration | default is 1 |
| `-n <num iteration>` | Num of perf run iteration | - |
| `-mt` | Max new tokens | - |
| `-h` | Show help message | - |

## Examples

### Prepare OpenVINO GenAI

```bash
pip install openvino-genai==2025.4.1.0
pip install librosa==0.11.0 pillow==12.0.0 json5==0.13.0
```

### Prepare VLM models
```bash
pip install optimum-intel[openvino]

optimum-cli export openvino --model <model_id> --weight-format fp16 <exported_model_name>

Examples:
optimum-cli export openvino --model Qwen/Qwen2-VL-2B --trust-remote-code --weight-format fp16 Qwen2-VL-2B
optimum-cli export openvino --model Qwen/Qwen2.5-VL-3B-Instruct --trust-remote-code --weight-format int8 Qwen2.5-VL-3B-Instruct

```

### Test Model
```bash

python3 visual_language_chat.py [-h] model_dir image_dir [device]

Examples:
python3 visual_language_chat.py /home/intel/models/Qwen2.5-VL-3B-Instruct/ test.jpg GPU
```

## Output

```
question:
what's this
This is a modern kitchen with a clean and minimalist design. Here are some key features:

1. **Cabinets and Countertops**: The kitchen has sleek, white cabinets and a matching white countertop. The cabinets are likely made of a light-colored material, possibly laminate or glass.

2. **Appliances**: There is a built-in stove with a glass cooktop and a microwave above it. The stove has a modern design with a glass panel.

3. **Utensils
----------
question:

```


## Benchmark Model

The benchmark uses OpenVINO's `benchmark_app` with the following settings:

```bash
python3 benchmark_vlm.py \
  -m <model path> \
  -i <image file> \
  -d GPU.0 

Examples:
python3 benchmark_vlm.py -m /home/intel/models/Qwen2.5-VL-3B-Instruct/ -d GPU -i test.jpg
```

## Understanding Results

```
Number of images:1, Prompt token size: 6
Output token size: 20
Load time: 10888.00 ms
Generate time: 1837.98 ± 7.57 ms
Tokenization time: 5.30 ± 0.07 ms
Detokenization time: 1.36 ± 0.41 ms
Embeddings preparation time: 1268.92 ± 0.00 ms
TTFT: 1420.97 ± 6.85 ms
TPOT: 21.83 ± 24.47 ms
Throughput : 45.81 ± 51.35 tokens/s
```
perf number description: mean ± std


## System Requirements

- **Container**: intel/dlstreamer:2025.2.0-ubuntu24
- **GPU**: Intel GPU with OpenVINO support
- **Software**: Docker, xpu-smi, OpenVINO toolkit, OpenVINO-genai 
- **Permissions**: sudo access for GPU monitoring
- **Storage**: Sufficient space for models and results

