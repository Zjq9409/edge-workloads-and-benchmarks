#!/usr/bin/env python3
# Copyright (C) 2023-2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

import sys
import argparse
import openvino_genai as ov_genai
from PIL import Image
from openvino import Tensor
from pathlib import Path
import numpy as np
from openvino import get_version
import cv2
import time

def read_image(path: str) -> Tensor:
    '''

    Args:
        path: The path to the image.

    Returns: the ov.Tensor containing the image.

    '''
    pic = Image.open(path).convert("RGB")
    image_data = np.array(pic)
    return Tensor(image_data)

def read_images(path: str) -> list[Tensor]:
    entry = Path(path)
    if entry.is_dir():
        return [read_image(str(file)) for file in sorted(entry.iterdir())]
    return [read_image(path)]

def read_video(path: str, num_frames: int = 8) -> Tensor:
    """

    Args:
        path: The path to the video.
        num_frames: Number of frames sampled from the video.

    Returns: the ov.Tensor containing the video.

    """
    cap = cv2.VideoCapture(path)

    frames = []
    total_num_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    indices = np.arange(0, total_num_frames, total_num_frames / num_frames).astype(int)

    idx = 0
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        if idx in indices:
            frames.append(np.array(frame))
        idx += 1

    cap.release()
    assert idx == total_num_frames, "Frame count mismatch: expected {}, got {}".format(total_num_frames, idx)

    return Tensor(frames)

def read_videos(path: str) -> list[Tensor]:
    entry = Path(path)
    if entry.is_dir():
        return [read_video(str(file)) for file in sorted(entry.iterdir())]
    return [read_video(path)]

def main():
    parser = argparse.ArgumentParser(description="Help command")
    parser.add_argument("-m", "--model", type=str, help="Path to model and tokenizers base directory")
    parser.add_argument("-p", "--prompt", type=str, default=None, help="Prompt")
    parser.add_argument("-pf", "--prompt_file", type=str, help="Read prompt from file")
    parser.add_argument("-i", "--image", type=str, default="image.jpg", help="Image")
    parser.add_argument("-nw", "--num_warmup", type=int, default=1, help="Number of warmup iterations")
    parser.add_argument("-n", "--num_iter", type=int, default=2, help="Number of iterations")
    parser.add_argument("-mt", "--max_new_tokens", type=int, default=20, help="Maximal number of new tokens")
    parser.add_argument("-d", "--device", type=str, default="CPU", help="Device")

    args = parser.parse_args()

    if args.prompt is not None and args.prompt_file is not None:
        raise RuntimeError(f'Prompt and prompt file should not exist together!')
    else:
        if args.prompt_file is not None:
            with open(args.prompt_file, 'r', encoding='utf-8') as f:
                prompt = f.read()
        else:
            prompt = 'What is on the image?' if args.prompt is None else args.prompt
    if len(prompt) == 0:
        raise RuntimeError(f'Prompt is empty!')

    print(f'openvino runtime version: {get_version()}, genai version: {ov_genai.__version__}')

    # Perf metrics is stored in VLMDecodedResults.
    # In order to get VLMDecodedResults instead of a string input should be a list.
    models_path = args.model
    # check if it is video or image by extension, only support mp4, avi, mov for video
    image_lower = args.image.lower()
    isvideo = image_lower.endswith('.mp4') or image_lower.endswith('.avi') or image_lower.endswith('.mov')
    if isvideo:
        images = read_videos(args.image)
    else:
        images = read_images(args.image)
    device = args.device
    num_warmup = args.num_warmup
    num_iter = args.num_iter

    config = ov_genai.GenerationConfig()
    config.max_new_tokens = args.max_new_tokens

    if device == "NPU":
        pipe = ov_genai.VLMPipeline(models_path, device)
    else:
        # Setting of Scheduler config will trigger usage of ContinuousBatching pipeline, which is not default for Qwen2VL, Qwen2.5VL, Gemma3 due to accuracy issues.
        scheduler_config = ov_genai.SchedulerConfig()
        scheduler_config.enable_prefix_caching = False
        scheduler_config.max_num_batched_tokens = sys.maxsize
        pipe = ov_genai.VLMPipeline(models_path, device, scheduler_config=scheduler_config)

    input_data = pipe.get_tokenizer().encode(prompt)
    prompt_token_size = input_data.input_ids.get_shape()[1]
    print(f"Number of images:{len(images)}, Prompt token size: {prompt_token_size}")

    for _ in range(num_warmup):
        if isvideo:
            pipe.generate(prompt, videos=images, generation_config=config)
        else:
            pipe.generate(prompt, images=images, generation_config=config)

    if isvideo:
        res = pipe.generate(prompt, videos=images, generation_config=config)
    else:
        res = pipe.generate(prompt, images=images, generation_config=config)
    perf_metrics = res.perf_metrics
    for _ in range(num_iter - 1):
        start_time = time.perf_counter()
        if isvideo:
            res = pipe.generate(prompt, videos=images, generation_config=config)
        else:
            res = pipe.generate(prompt, images=images, generation_config=config)
        perf_metrics += res.perf_metrics
        end_time = time.perf_counter()
        print(f"Iteration time: {(end_time - start_time) * 1000:.2f} ms")

    print(f"Output token size: {res.perf_metrics.get_num_generated_tokens()}")
    print(f"Load time: {perf_metrics.get_load_time():.2f} ms")
    print(
        f"Generate time: {perf_metrics.get_generate_duration().mean:.2f} ± {perf_metrics.get_generate_duration().std:.2f} ms")
    print(
        f"Tokenization time: {perf_metrics.get_tokenization_duration().mean:.2f} ± {perf_metrics.get_tokenization_duration().std:.2f} ms")
    print(
        f"Detokenization time: {perf_metrics.get_detokenization_duration().mean:.2f} ± {perf_metrics.get_detokenization_duration().std:.2f} ms")
    print(
        f"Embeddings preparation time: {perf_metrics.get_prepare_embeddings_duration().mean:.2f} ± {perf_metrics.get_prepare_embeddings_duration().std:.2f} ms")
    print(f"TTFT: {perf_metrics.get_ttft().mean:.2f} ± {perf_metrics.get_ttft().std:.2f} ms")
    print(f"TPOT: {perf_metrics.get_tpot().mean:.2f} ± {perf_metrics.get_tpot().std:.2f} ms")
    print(f"Throughput : {perf_metrics.get_throughput().mean:.2f} ± {perf_metrics.get_throughput().std:.2f} tokens/s")


if __name__ == "__main__":
    main()
