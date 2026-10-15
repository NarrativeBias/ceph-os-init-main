#!/bin/bash
# Split each "empty" NVMe controller (no namespaces n2..n9) into two equal
# namespaces. Sizes come from a JSON dict: { "MODEL": nsze, ... }.
#
# Already-split controllers (n2+ present):
#   - always fail if any namespace has an LVM PV (not skippable)
#   - fail unless OSD_NVME_ALLOW_ALREADY_SPLIT=1 (then skip those ctrls)
#
# Usage: split-nvme-namespaces.sh /path/to/models.json

set -euo pipefail

models_json=${1:?usage: $0 models.json}
ctrl_glob=${OSD_NVME_CTRL_GLOB:-/sys/class/nvme/nvme[0-7]}
allow_already_split=${OSD_NVME_ALLOW_ALREADY_SPLIT:-0}

is_split() {
  local ctrl=$1 n
  for n in 2 3 4 5 6 7 8 9; do
    if [[ -e /dev/${ctrl}n${n} ]]; then
      return 0
    fi
  done
  return 1
}

# True if any namespace of this controller is an LVM PV.
has_lvm() {
  local ctrl=$1 n dev
  for n in 1 2 3 4 5 6 7 8 9; do
    dev="/dev/${ctrl}n${n}"
    [[ -e $dev ]] || continue
    if pvs --noheadings "$dev" &>/dev/null; then
      echo "$dev"
      return 0
    fi
  done
  return 1
}

declare -a empty_nvme=()
declare -a already_split=()
declare -a split_with_lvm=()

for path in $ctrl_glob; do
  [[ -e $path ]] || continue
  ctrl=$(basename "$path")
  if is_split "$ctrl"; then
    if pv=$(has_lvm "$ctrl"); then
      split_with_lvm+=("${ctrl} (${pv})")
    else
      already_split+=("$ctrl")
    fi
  else
    empty_nvme+=("$ctrl")
  fi
done

if [[ ${#split_with_lvm[@]} -gt 0 ]]; then
  echo "ERROR: already-split NVMe with LVM present (cannot skip):" >&2
  printf '  %s\n' "${split_with_lvm[@]}" >&2
  exit 1
fi

if [[ ${#already_split[@]} -gt 0 ]]; then
  if [[ "$allow_already_split" != "1" && "$allow_already_split" != "true" && "$allow_already_split" != "True" ]]; then
    echo "ERROR: NVMe already split (no LVM). Re-run with osd_nvme_allow_already_split=true to skip:" >&2
    printf '  %s\n' "${already_split[@]}" >&2
    exit 1
  fi
  echo "Skipping already-split NVMe (osd_nvme_allow_already_split): ${already_split[*]}"
fi

if [[ ${#empty_nvme[@]} -eq 0 ]]; then
  if [[ ${#already_split[@]} -gt 0 ]]; then
    echo "No empty NVMe controllers left to split."
    exit 0
  fi
  echo "ERROR: no NVMe controllers matched ${ctrl_glob}" >&2
  exit 1
fi

rescan() {
  local ctrl=$1
  echo 1 >"/sys/class/nvme/${ctrl}/rescan_controller"
  sleep 1
}

declare -a split_list=()

for ctrl in "${empty_nvme[@]}"; do
  model=$(tr -d '[:space:]' <"/sys/class/nvme/${ctrl}/model")
  nszencap=$(
    python3 -c '
import json, sys
models = json.load(open(sys.argv[1]))
model = sys.argv[2]
if model not in models:
    print("unknown", file=sys.stderr)
    sys.exit(2)
print(int(models[model]))
' "$models_json" "$model"
  ) || {
    echo "Unknown NVMe model on ${ctrl}: '${model}' (not in osd_nvme_namespace_sizes)" >&2
    exit 1
  }

  echo "Splitting ${ctrl} model=${model} nsze=${nszencap}"

  nvme delete-ns "/dev/${ctrl}" -n 1 || true
  nvme delete-ns "/dev/${ctrl}" -n 2 || true
  rescan "$ctrl"

  nvme create-ns "/dev/${ctrl}" --nsze="$nszencap" --ncap="$nszencap" --flbas=0 --dps=0
  rescan "$ctrl"
  nvme create-ns "/dev/${ctrl}" --nsze="$nszencap" --ncap="$nszencap" --flbas=0 --dps=0
  rescan "$ctrl"

  cntlid=$(nvme id-ctrl "/dev/${ctrl}" | awk '/cntlid/ {print $3; exit}')
  nvme attach-ns "/dev/${ctrl}" -n 1 -c "$cntlid"
  rescan "$ctrl"
  nvme attach-ns "/dev/${ctrl}" -n 2 -c "$cntlid"
  rescan "$ctrl"

  split_list+=("$ctrl")
done

echo "Split NVMe controllers: ${split_list[*]}"
