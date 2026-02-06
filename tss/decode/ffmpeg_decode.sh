#!/bin/bash
# Usage
# sudo ./ffmpeg_decode.sh h265|h264 video #stream
# such as "sudo ./ffmpeg_decode.sh h265 videosource/gameLOL_1920x1080_30.h265 122"
# How to build ffmpeg
# 	wget https://ffmpeg.org/releases/ffmpeg-7.1.1.tar.xz
# 	tar xvf ffmpeg-7.1.1.tar.xz
# 	cd ffmpeg-7.1.1
# 	sudo apt install nasm pkg-config libvpl-dev libx264-dev libx265-dev libva-dev
# 	./configure --enable-shared --extra-cflags=-w --enable-nonfree --disable-xlib --enable-libvpl --enable-vaapi --enable-gpl --enable-libx264 --enable-gpl --enable-libx265
# 	make -j
# 	make install
# 	sudo ldconfig
#
OUTPUTDIR="output"

format=$1
input=$2
nbInParallel=$3

mkdir -p $OUTPUTDIR
rm -f $OUTPUTDIR/${input##*/}-${format}-*-log.txt

while [ $nbInParallel -gt 0 ]; do
	let nbInParallel=nbInParallel-1
	output=$OUTPUTDIR/${input##*/}-${format}-$nbInParallel.yuv
	logfile=$OUTPUTDIR/${input##*/}-${format}-$nbInParallel-log.txt
	array=${input#*\_}
	resolution=${array%%\_*}
	framerate=${array#*\_}
	framerate=${framerate%%\.*}
	if [ "$format" = "h264" ]
	then
		ffmpeg -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 -hwaccel_output_format vaapi -i $input -low_power on -f null -  &> $logfile &
	elif [ "$format" = "h265" ]
	then
		ffmpeg -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 -hwaccel_output_format vaapi -i $input -low_power on -f null -  &> $logfile &
	fi
done
wait
sum_fps=`sed '{s/\r/\n/g}' $OUTPUTDIR/${input##*/}-${format}-*-log.txt | grep Lsize |tr '=' ' '| awk 'BEGIN{sum=0;}{sum+=$4;}END{print sum;}'`
avg_fps=$(awk 'BEGIN{printf "%.1f\n",'$sum_fps'/'$3'}')
min_fps=`sed '{s/\r/\n/g}' $OUTPUTDIR/${input##*/}-${format}-*-log.txt | grep Lsize |tr '=' ' '|awk '{print $4"."}'|sort -n | head -1`
echo "$format, $input, #stream: $3, total fps: $sum_fps, average fps: $avg_fps, min fps: $min_fps"
echo $(sed '{s/\r/\n/g}' $OUTPUTDIR/${input##*/}-${format}-*-log.txt | grep Lsize |tr '=' ' '|awk '{print $4"."}'|sort|uniq -c|sort -nr)
