#!/usr/bin/env python3
# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
"""
Download google/vit-base-patch32-224-in21k from HuggingFace,
convert to OpenVINO IR (FP16), and quantize to INT8 using local COCO val2017.
"""

import argparse
import glob
import logging
import random
from pathlib import Path

import numpy as np
import nncf
import openvino as ov
from PIL import Image
from tqdm import tqdm
from transformers import ViTImageProcessor, ViTModel


IMG_SIZE = 224
MEAN = np.array([0.5, 0.5, 0.5], dtype=np.float32)
STD  = np.array([0.5, 0.5, 0.5], dtype=np.float32)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Convert and quantize ViT-base-patch32-224-in21k to INT8 OpenVINO IR"
    )
    parser.add_argument(
        "-o", "--output",
        default="models/vit-base-patch32-224",
        help="Output directory for model files",
    )
    parser.add_argument(
        "-i", "--image-dir",
        default="datasets/coco/images/val2017",
        help="Directory of JPEG images for INT8 calibration (COCO val2017)",
    )
    parser.add_argument(
        "-n", "--num-samples",
        type=int,
        default=300,
        help="Number of calibration samples (default: 300)",
    )
    return parser.parse_args()


def preprocess(path: str) -> np.ndarray:
    img = Image.open(path).convert("RGB").resize((IMG_SIZE, IMG_SIZE), Image.BILINEAR)
    arr = np.array(img, dtype=np.float32) / 255.0
    arr = (arr - MEAN) / STD
    return arr.transpose(2, 0, 1)[np.newaxis]   # [1, 3, 224, 224]


def prepare_dataset(image_dir: str, n: int) -> list:
    paths = sorted(glob.glob(f"{image_dir}/*.jpg"))
    if len(paths) == 0:
        raise RuntimeError(f"No JPEG images found in {image_dir}")
    random.seed(42)
    selected = random.sample(paths, min(n, len(paths)))
    data = []
    print(f"[ Info ] Loading {len(selected)} calibration images from {image_dir} ...")
    for p in tqdm(selected):
        try:
            data.append({"pixel_values": preprocess(p)})
        except Exception as e:
            print(f"  Skipping {p}: {e}")
    return data


def main():
    args = parse_args()
    outdir = Path(args.output)
    outdir.mkdir(parents=True, exist_ok=True)

    fp16_xml = outdir / "vit-base-patch32-224-in21k.xml"
    fp16_bin = outdir / "vit-base-patch32-224-in21k.bin"
    int8_xml  = outdir / "vit-base-patch32-224-in21k_int8.xml"
    int8_bin  = outdir / "vit-base-patch32-224-in21k_int8.bin"

    # 1. Download and convert to OpenVINO IR (FP16)
    if fp16_xml.exists() and fp16_bin.exists():
        print(f"[ Info ] FP16 model already exists: {fp16_xml}")
    else:
        print("[ Info ] Downloading google/vit-base-patch32-224-in21k ...")
        processor = ViTImageProcessor.from_pretrained("google/vit-base-patch32-224-in21k")
        model = ViTModel.from_pretrained("google/vit-base-patch32-224-in21k")
        model.eval()

        dummy_img = Image.fromarray(np.zeros((IMG_SIZE, IMG_SIZE, 3), dtype=np.uint8))
        inputs = processor(images=dummy_img, return_tensors="pt")

        print("[ Info ] Converting to OpenVINO IR (FP16) ...")
        model.config.torchscript = True
        ov_model = ov.convert_model(
            model,
            example_input=dict(inputs),
            input=[(-1, 3, IMG_SIZE, IMG_SIZE)],
        )
        ov.save_model(ov_model, str(fp16_xml), compress_to_fp16=True)
        print(f"[ Info ] Saved FP16 model to {fp16_xml}")

    # 2. Quantize to INT8 using local COCO val2017 images
    if int8_xml.exists() and int8_bin.exists():
        print(f"[ Info ] INT8 model already exists: {int8_xml}")
    else:
        calibration_data = prepare_dataset(args.image_dir, args.num_samples)
        if len(calibration_data) == 0:
            raise RuntimeError(f"No calibration data loaded from {args.image_dir}")

        print("[ Info ] Loading FP16 model for quantization ...")
        nncf.set_log_level(logging.ERROR)
        core = ov.Core()
        ov_model = core.read_model(str(fp16_xml))

        print("[ Info ] Quantizing to INT8 (TRANSFORMER + SmoothQuant) ...")
        calibration_dataset = nncf.Dataset(calibration_data)
        quantized_model = nncf.quantize(
            model=ov_model,
            calibration_dataset=calibration_dataset,
            model_type=nncf.ModelType.TRANSFORMER,
            preset=nncf.QuantizationPreset.PERFORMANCE,
            advanced_parameters=nncf.AdvancedQuantizationParameters(
                smooth_quant_alpha=0.6
            ),
        )
        ov.save_model(quantized_model, str(int8_xml))
        print(f"[ Info ] Saved INT8 model to {int8_xml}")

    # Report sizes
    if fp16_bin.exists() and int8_bin.exists():
        fp16_mb = fp16_bin.stat().st_size / 1024 / 1024
        int8_mb  = int8_bin.stat().st_size  / 1024 / 1024
        print(f"[ Info ] FP16: {fp16_mb:.1f} MB  |  INT8: {int8_mb:.1f} MB  |  Compression: {fp16_mb / int8_mb:.2f}x")


if __name__ == "__main__":
    main()
