#!/bin/bash

BASEDIR=$(dirname $0)
rpm -Uvh ${BASEDIR}/rpm/*.rpm

PATH=$PATH:/opt/MegaRAID/perccli

CTRL_COUNT=$(perccli64 show ctrlcount | awk -F= /Count/'{print $2}')

for (( CTRL_IDX=0; CTRL_IDX<CTRL_COUNT; CTRL_IDX++)); do
  echo "Controller = "$CTRL_IDX;

  EID=$(perccli64 /c${CTRL_IDX} /eall show | awk -F' ' /OK/'{ if ($4 > 0) {print $1} }')
  if [[ ! -z "${EID}" ]]; then
    echo "EID = "$EID

    VG_IDX=0
    for DISK in $(perccli64 /c${CTRL_IDX} /eall /sall show | awk -F':| ' /${EID}:/'{print $2}' | xargs); do
      OS_CMD="
      perccli64 /c${CTRL_IDX}/e${EID}/s${DISK} set good force;
      perccli64 /c${CTRL_IDX} add vd r0 name=SLOT_${DISK} drives=${EID}:${DISK} pdcache=on wb ra direct Strip=64;
      perccli64 /c${CTRL_IDX}/v${VG_IDX} set bootdrive=off;
      perccli64 /c${CTRL_IDX}/v${VG_IDX} start init force;
      "
      echo ${OS_CMD};
      eval ${OS_CMD};

      ((VG_IDX++))
    done

    perccli64 /c${CTRL_IDX} set bios state=off
    perccli64 /c${CTRL_IDX} set bios abs=off
    perccli64 /c${CTRL_IDX} set eghs state=on
    perccli64 /c${CTRL_IDX} set largeiosupport=on
    perccli64 /c${CTRL_IDX} set jbod=off
    perccli64 /c${CTRL_IDX} set autoconfig=none
  fi;
done
