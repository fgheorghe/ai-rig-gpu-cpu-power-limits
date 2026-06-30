#!/bin/bash
echo "applying gpu power config..."
/usr/local/bin/gpu_power_limit.sh || echo "gpu config failed with exit code $?"
echo "gpu config applied, idling"
exec sleep infinity
