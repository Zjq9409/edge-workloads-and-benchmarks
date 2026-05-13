model_path="/home/intel/media_ai/edge-workloads-and-benchmarks/model-conversion/models/yolo11s/yolo11s_fp32.xml"
DEVICE=GPU.0
benchmark_app -m ${model_path} --batch_size 1 -d ${DEVICE} -hint throughput -shape [1,3,640,640]
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
benchmark_app -m ${model_path} --batch_size 8 -d ${DEVICE} -hint throughput -shape [8,3,640,640]
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
model_path="/home/intel/media_ai/edge-workloads-and-benchmarks/model-conversion/models/yolo11s/yolo11s_int8.xml"
benchmark_app -m ${model_path} --batch_size 1 -d ${DEVICE} -hint throughput -shape [1,3,640,640]
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
benchmark_app -m ${model_path} --batch_size 8 -d ${DEVICE} -hint throughput -shape [8,3,640,640]
