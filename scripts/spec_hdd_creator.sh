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
unmanaged: true
spec:
  data_devices:
    rotational: 1
  db_devices:
    rotational: 0
  filter_logic: AND
  objectstore: bluestore" >> osds.spec
   fi
   i=$[i+1]
done < "$input"

