#!/bin/bash
#nvme SAMSUNG MZQL215THBLA-00A07 nsze 14900000000
#nvme SAMSUNG MZQL27T6HBLA-00A07 nsze 7400000000
#nvme INTEL   SSDPF2KX153T1      nsze 15000000000


for i in /dev/nvme0 /dev/nvme1 /dev/nvme2 /dev/nvme3 /dev/nvme4 /dev/nvme5 /dev/nvme6 /dev/nvme7; do sudo nvme delete-ns $i -n 1; sudo nvme delete-ns $i -n 2; done
echo 1 | sudo tee /sys/class/nvme/nvme*/rescan_controller
for i in /dev/nvme0 /dev/nvme1 /dev/nvme2 /dev/nvme3 /dev/nvme4 /dev/nvme5 /dev/nvme6 /dev/nvme7; do sudo nvme create-ns $i --nsze=7400000000 --ncap=7400000000  --flbas=0 --dps=0;done
echo 1 | sudo tee /sys/class/nvme/nvme*/rescan_controller
for i in /dev/nvme0 /dev/nvme1 /dev/nvme2 /dev/nvme3 /dev/nvme4 /dev/nvme5 /dev/nvme6 /dev/nvme7; do sudo nvme create-ns $i --nsze=7400000000 --ncap=7400000000  --flbas=0 --dps=0;done
echo 1 | sudo tee /sys/class/nvme/nvme*/rescan_controller
for i in /dev/nvme0 /dev/nvme1 /dev/nvme2 /dev/nvme3 /dev/nvme4 /dev/nvme5 /dev/nvme6 /dev/nvme7; do sudo nvme attach-ns $i --namespace-id=1 --controller=$(sudo nvme id-ctrl $i | grep cntlid | awk '{print $3}'); done
echo 1 | sudo tee /sys/class/nvme/nvme*/rescan_controller
for i in /dev/nvme0 /dev/nvme1 /dev/nvme2 /dev/nvme3 /dev/nvme4 /dev/nvme5 /dev/nvme6 /dev/nvme7; do sudo nvme attach-ns $i --namespace-id=2 --controller=$(sudo nvme id-ctrl $i | grep cntlid | awk '{print $3}'); done
echo 1 | sudo tee /sys/class/nvme/nvme*/rescan_controller
