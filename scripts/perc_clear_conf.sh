#!/bin/bash

BASEDIR=$(dirname $0)
rpm -Uvh ${BASEDIR}/rpm/*.rpm

PATH=$PATH:/opt/MegaRAID/perccli

CTRL_COUNT=$(perccli64 show ctrlcount | awk -F= /Count/'{print $2}')

for (( CTRL_IDX=0; CTRL_IDX<CTRL_COUNT; CTRL_IDX++)); do
  perccli64 /c${CTRL_IDX} delete config force
  perccli64 /c${CTRL_IDX} /fall delete
  perccli64 /c${CTRL_IDX} delete config force
  perccli64 /c${CTRL_IDX} delete events
  perccli64 /c${CTRL_IDX} erase all
done
