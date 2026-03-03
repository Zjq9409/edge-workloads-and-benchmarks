# use gstreamer to do E2E workload by calling vLLM service and doing VL models

## Purpose

Demonstrate how to leverage gstreamer to ingtegrate media+ov+vllm together

## Steps to run

### Preparation

1. test media video, e.g. test.mp4
2. ov detection model is ready
3. vLLM VL service is ready

### cmd options
```bash

./call_vlm_on_saved_frame.sh <test video> <OV detect model> <OV GPU device>  <output>

```

### Example
```bash

./call_vlm_on_saved_frame.sh test.mp4 yolo11n/FP16/yolo11n.xml GOU.0

```
