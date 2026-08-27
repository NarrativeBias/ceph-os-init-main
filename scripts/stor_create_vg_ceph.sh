#!/bin/bash

BASEDIR=$(dirname $0)
rpm -Uvh ${BASEDIR}/rpm/*.rpm

PATH=$PATH:/opt/MegaRAID/storcli

CTRL_COUNT=$(storcli show ctrlcount | awk -F= /Count/'{print $2}')

for (( CTRL_IDX=0; CTRL_IDX<CTRL_COUNT; CTRL_IDX++)); do
  echo "Controller = "$CTRL_IDX;

  EID=$(storcli /c${CTRL_IDX} /eall show | awk -F' ' /OK/'{ if ($4 > 0) {print $1} }')
  NON_OS=$(storcli /c${CTRL_IDX} show | grep "Product Name" | awk '{print $4}')
  if [[ ! -z "${EID}" ]] && [[ "${NON_OS}" == "SAS3508" ]]; then
    echo "EID = "$EID

    VG_IDX=0
    for DISK in $(storcli /c${CTRL_IDX} /eall /sall show | awk -F':| ' /${EID}:/'{print $2}' | xargs); do
      OS_CMD="
      storcli /c${CTRL_IDX}/e${EID}/s${DISK} set good force;
      storcli /c${CTRL_IDX} add vd r0 name=SLOT_${DISK} drives=${EID}:${DISK} pdcache=on wb ra direct Strip=64;
      storcli /c${CTRL_IDX}/v${VG_IDX} set bootdrive=off;
      storcli /c${CTRL_IDX}/v${VG_IDX} start init force;
      "
      echo ${OS_CMD};
      eval ${OS_CMD};

      ((VG_IDX++))
    done

    storcli /c${CTRL_IDX} set bios state=off
    storcli /c${CTRL_IDX} set bios abs=off
    storcli /c${CTRL_IDX} set eghs state=on
    storcli /c${CTRL_IDX} set largeiosupport=on
    storcli /c${CTRL_IDX} set jbod=off
    storcli /c${CTRL_IDX} set autoconfig=none
  fi;
done