#!/bin/bash
i=1
input="new_osd.spec"
HOST=""
SUFFIX=""
while IFS= read -r line
do
   if [ $((i)) == 1 ]
      then
         SUFFIX=$(echo "$line")
      else
         HOST=$(echo "$line")
         echo $HOST
         echo "---
service_type: osd
service_id: "$HOST"
service_name: osd."$HOST"
placement:
  hosts:
  - "$HOST""$SUFFIX"
unmanaged: false
spec:
  data_devices:
    paths:
    - /dev/nvme0n1
    - /dev/nvme1n1
    - /dev/nvme2n1
    - /dev/nvme3n1
    - /dev/nvme4n1
    - /dev/nvme5n1
    - /dev/nvme6n1
    - /dev/nvme7n1
    - /dev/nvme0n2
    - /dev/nvme1n2
    - /dev/nvme2n2
    - /dev/nvme3n2
    - /dev/nvme4n2
    - /dev/nvme5n2
    - /dev/nvme6n2
    - /dev/nvme7n2
  filter_logic: AND
  objectstore: bluestore" >> osds.spec
   fi
   i=$[i+1]
done < "$input"

