#!/bin/bash
set -uo pipefail

CONFIG="${GPU_CONFIG_PATH:-/etc/gpu-config/config.ini}"

if ! command -v crudini &>/dev/null; then
  echo "error: crudini not installed"
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "error: config file not found: $CONFIG"
  exit 1
fi

# check if overdrive is enabled (bit 14 = 0x4000)
ppfm_path="/sys/module/amdgpu/parameters/ppfeaturemask"
if [[ -f "$ppfm_path" ]]; then
  ppfm=$(cat "$ppfm_path")
  if (( (ppfm & 0x4000) == 0 )); then
    echo "warning: amdgpu overdrive disabled (ppfeaturemask=$(printf '0x%x' "$ppfm"))"
    echo "  SCLK offset will not work — add amdgpu.ppfeaturemask=0xffffffff to kernel params"
  else
    echo "overdrive enabled (ppfeaturemask=$(printf '0x%x' "$ppfm"))"
  fi
else
  echo "warning: amdgpu not loaded, SCLK offset will not work"
fi

find_card_by_pci() {
  local target="$1"
  for uevent in /sys/class/drm/card[0-9]*/device/uevent; do
    if grep -q "PCI_SLOT_NAME=${target}$" "$uevent" 2>/dev/null; then
      echo "${uevent%/device/uevent}"
      return 0
    fi
  done
  return 1
}

find_hwmon() {
  local card_dir="$1"
  for d in "$card_dir"/device/hwmon/hwmon*/; do
    [[ -f "${d}power1_cap" ]] && { echo "$d"; return 0; }
  done
  return 1
}

i=0
while true; do
  section="gpu:$i"
  if ! pci_slot=$(crudini --get "$CONFIG" "$section" pci_slot 2>/dev/null); then
    break
  fi

  echo "=== $section ($pci_slot) ==="

  card_dir=$(find_card_by_pci "$pci_slot") || {
    echo "  warning: PCI slot $pci_slot not found, skipping"
    ((i++)); continue
  }

  hwmon_dir=$(find_hwmon "$card_dir") || {
    echo "  warning: no hwmon for $pci_slot, skipping"
    ((i++)); continue
  }

  # --- power cap (microwatts) ---
  if max_wattage=$(crudini --get "$CONFIG" "$section" max_wattage 2>/dev/null); then
    echo "  setting power cap to ${max_wattage}W"
    echo "$((max_wattage * 1000000))" > "${hwmon_dir}power1_cap"
  elif [[ -f "${hwmon_dir}power1_cap_default" ]]; then
    default_uw=$(cat "${hwmon_dir}power1_cap_default")
    echo "  resetting power cap to default ($((default_uw / 1000000))W)"
    echo "$default_uw" > "${hwmon_dir}power1_cap"
  fi

  # --- overdrive settings (all require amdgpu.ppfeaturemask=0xffffffff) ---
  pp_od="${card_dir}/device/pp_od_clk_voltage"
  perf_lvl="${card_dir}/device/power_dpm_force_performance_level"

  sclk_offset=$(crudini --get "$CONFIG" "$section" sclk_offset 2>/dev/null) || true
  mclk=$(crudini --get "$CONFIG" "$section" mclk 2>/dev/null) || true
  vddgfx_offset=$(crudini --get "$CONFIG" "$section" vddgfx_offset 2>/dev/null) || true

  if [[ -n "$sclk_offset" || -n "$mclk" || -n "$vddgfx_offset" ]]; then
    if [[ -f "$pp_od" && -f "$perf_lvl" ]]; then
      echo "  resetting OD before applying"
      echo "r" > "$pp_od" 2>/dev/null
      echo "c" > "$pp_od" 2>/dev/null
      echo "  perf level -> manual"
      echo "manual" > "$perf_lvl"
      [[ -n "$sclk_offset" ]] && echo "  SCLK offset ${sclk_offset}MHz" && echo "s ${sclk_offset}" > "$pp_od"
      [[ -n "$mclk" ]] && echo "  MCLK -> ${mclk}MHz" && echo "m 1 ${mclk}" > "$pp_od"
      [[ -n "$vddgfx_offset" ]] && echo "  VDDGFX offset ${vddgfx_offset}mV" && echo "vo ${vddgfx_offset}" > "$pp_od"
      echo "c" > "$pp_od"
    else
      echo "  warning: pp_od_clk_voltage unavailable (need amdgpu.ppfeaturemask=0xffffffff)"
    fi
  elif [[ -f "$pp_od" && -f "$perf_lvl" ]]; then
    echo "  resetting clocks to default"
    echo "r" > "$pp_od" 2>/dev/null
    echo "c" > "$pp_od" 2>/dev/null
    echo "auto" > "$perf_lvl" 2>/dev/null
  fi

  ((i++))
done

if [[ $i -eq 0 ]]; then
  echo "no gpu sections found in $CONFIG"
  exit 1
fi

echo "done, configured $i gpu(s)"
