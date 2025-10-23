#!/bin/bash
# set_cpu_performance.sh - Set CPU governor to performance mode for better audio
# This reduces audio crackling by preventing CPU frequency scaling

echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null

echo "CPU governor set to performance mode:"
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
