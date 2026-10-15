#!/bin/bash
# Split each "empty" NVMe controller (no namespaces n2..n9) into two equal
# namespaces. Sizes come from a JSON dict: { "MODEL": nsze, ... }.
# Non-interactive. Unknown models among empty controllers → exit 1.
#
# Usage: split-nvme-namespaces.sh /path/to/models.json

set -euo pipefail

models_json=${1:?usage: $0 models.json}
ctrl_glob=${OSD_NVME_CTRL_GLOB:-/sys/class/nvme/nvme[0-7]}

mapfile -t empty_nvme < <(
  for path in $ctrl_glob; do
    [[ -e $path ]] || continue
    ctrl=$(basename "$path")
    empty=1
    for n in 2 3 4 5 6 7 8 9; do
      if [[ -e /dev/${ctrl}n${n} ]]; then
        empty=0
        break
      fi
    done
    if [[ $empty -eq 1 ]]; then
      printf '%s\n' "$ctrl"
    fi
  done
)

if [[ ${#empty_nvme[@]} -eq 0 ]]; then
  echo "No empty NVMe controllers (already split or none present); nothing to do."
  exit 0
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
