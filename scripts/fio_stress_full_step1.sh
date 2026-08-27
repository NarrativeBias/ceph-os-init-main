#!/bin/bash
disks=(rbd0 rbd1 rbd2 rbd3 rbd4 rbd5 rbd6 rbd7 rbd8 rbd9 rbd10 rbd11 rbd12 rbd13 rbd14 rbd15 rbd16 rbd17 rbd18 rbd19 rbd20 rbd21 rbd22 rbd23)
rw_name=(randwrite randread randrw)
block_size=(2 8 32 128)
max_jobs=(1)
iodepth=(2 4 8)
mixread=(50 65)
disksBackup="${disks[@]}"
disksLen=${#disks[@]}
runtime=600
host=`hostname -s`
for test_type in "${rw_name[@]}"; do
cur_dir=/var/tmp/bandfio
for bs in "${block_size[@]}"; do
for mj in "${max_jobs[@]}"; do
for iod in "${iodepth[@]}"; do
if ! [ -d $cur_dir ]; then
mkdir $cur_dir
fi
for (( i=disksLen; i<=disksLen; i++ )); do      #increase "i" if you want to test less disks in same time
if [ "${test_type}" != "randrw" ]; then
for disk in "${disks[@]}" ; do
filename=const_${host}_${disk}_${test_type}_${bs}k_${mj}_${iod}_${#disks[@]}_stress.`hostname -s`.json
/usr/bin/fio --name ${host} --filename=/dev/${disk} --ioengine=libaio --direct=1 --gtod_reduce=0 --rw=${test_type} \
--bs=${bs}k --max-jobs=${mj} --iodepth=${iod} --runtime=${runtime} --output-format=json+ --output=$cur_dir/$filename &
done
else
for mr in "${mixread[@]}"; do
for disk in "${disks[@]}" ; do
filename=const_${host}_${disk}_${test_type}_${bs}k_${mj}_${iod}_${mr}_${#disks[@]}_stress.`hostname -s`.json
/usr/bin/fio --name ${host} --filename=/dev/${disk} --ioengine=libaio --direct=1 --gtod_reduce=0 --rw=${test_type} \
--bs=${bs}k --max-jobs=${mj} --iodepth=${iod} --runtime=${runtime} --rwmixread=${mr} --output-format=json+ --output=$cur_dir/$filename &
done
wait
done
fi
wait
disks=("${disks[@]::${#disks[@]}-1}")
done
disks=(${disksBackup[@]})
done
done
done
done
