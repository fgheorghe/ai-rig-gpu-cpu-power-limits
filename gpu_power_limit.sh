#!/bin/bash
set -uo pipefail

CONFIG="${GPU_CONFIG_PATH:-/etc/gpu-config/config.ini}"

if ! command -v crudini &>/dev/null; then
  echo "error: crudini not installed (apt install crudini)"
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "error: config file not found: $CONFIG"
  exit 1
fi

i=0
while true; do
  section="gpu:$i"
  if ! uuid=$(crudini --get "$CONFIG" "$section" uuid 2>/dev/null); then
    break
  fi

  echo "=== $section ($uuid) ==="

  dev_index=$(nvidia-smi -L | grep -i "$uuid" | head -1 | sed 's/GPU \([0-9]*\):.*/\1/')
  if [[ -z "$dev_index" ]]; then
    echo "  warning: UUID $uuid not found on this system, skipping"
    ((i++))
    continue
  fi

  echo "  enabling persistence mode"
  nvidia-smi -i "$dev_index" -pm 1

  if max_wattage=$(crudini --get "$CONFIG" "$section" max_wattage 2>/dev/null); then
    echo "  setting power limit to ${max_wattage}W"
    nvidia-smi -i "$dev_index" -pl "$max_wattage"
  else
    default_pl=$(nvidia-smi -i "$dev_index" --query-gpu=power.default_limit --format=csv,noheader,nounits | xargs)
    echo "  resetting power limit to default (${default_pl}W)"
    nvidia-smi -i "$dev_index" -pl "$default_pl"
  fi

  if max_freq=$(crudini --get "$CONFIG" "$section" max_freq 2>/dev/null); then
    echo "  locking max clock to ${max_freq}MHz"
    nvidia-smi -i "$dev_index" -lgc "$max_freq"
  else
    echo "  resetting clocks to default"
    nvidia-smi -i "$dev_index" -rgc
  fi

  ((i++))
done

if [[ $i -eq 0 ]]; then
  echo "no gpu sections found in $CONFIG"
  exit 1
fi

echo "done, configured $i gpu(s)"
