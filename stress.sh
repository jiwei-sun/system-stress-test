#!/bin/bash

cpu_stress_test()
{
	processor=`cat /proc/cpuinfo |grep "processor" |wc -l`
	task=$(($processor/2))
	if [ $task -lt 1 ]; then
		task=1
	fi
	stress -c $task &
}

memory_stress_test()
{
	processor=`cat /proc/cpuinfo |grep "processor" |wc -l`
	task=$processor
	timeout=30
	free -m > /tmp/free
	sed -i "1d;3d" /tmp/free
	total=`cat /tmp/free | awk -F " " '{print $2}'`
	available=`cat /tmp/free | awk -F " " '{print $7}'`
	rm /tmp/free
	if [ $available -gt 512 ]; then
		bytes=$(($available-512))
		bytes=$(($bytes/$task))
	elif [ $available -gt 128 ]; then
		bytes=$(($available-128))
		bytes=$(($bytes/$task))
	else
		bytes=$(($bytes/$task))
	fi
	stress --vm $task --vm-bytes "$bytes"M --vm-hang $timeout &
}

io_stress_test()
{
	processor=`cat /proc/cpuinfo |grep "processor" |wc -l`
	task=$(($processor/2))
	if [ $task -lt 1 ]; then
		task=1
	fi
	stress --io $task &
}

disk_stress_test()
{
	#fdisk -l |grep -E "Disk /dev/s|Disk /dev/nvme" > ./fdisk.log
	#cat ./fdisk.log | awk -F " " '{print $2}' > ./fdisk.log.tmp
	#cat ./fdisk.log.tmp | awk -F ":" '{print $1}' > ./fdisk.log
	#rm -f ./fdisk.log.tmp
	fdisk -l | grep -E -o '/dev/nvme[0-9]n[0-9]:|/dev/sd[a-z]:' | cut -d : -f 1 > ./fdisk.log
	cat /proc/mounts > ./mounts
	while read line
	do
		fdisk -l $line | grep "^$line" > ./disk.part
		if [ $? -eq 1 ]; then
			cat ./mounts | grep $line > ./part.mount
			if [ $? -eq 0 ];then
				df $line > ./df.log
				sed -i "1d" ./df.log
				space=`cat ./df.log | awk -F " " '{print $4}'`
				mounts_point=`cat ./part.mount | awk -F " " '{print $2}'`
				cd $mounts_point
				task=2
				space=$(($space/1024/2))M
				echo $line $space
				stress --hdd $task --hdd-bytes $space &
				cd -
				rm -f ./df.log
			fi
			rm -f ./part.mount
		else
			cat ./disk.part | awk -F " " '{print $1}' > ./disk.part.tmp
			while read PART
			do
				cat ./mounts | grep $PART > ./part.mount
				if [ $? -eq 0 ];then
					df  $PART > ./df.log
					sed -i "1d" ./df.log
					space=`cat ./df.log | awk -F " " '{print $4}'`
					mounts_point=`cat ./part.mount | awk -F " " '{print $2}'`
					cd $mounts_point
					task=2
					space=$(($space/1024/2))M
					echo $line $space
					stress --hdd $task --hdd-bytes $space &
					cd -
					rm -f ./df.log
				fi
				rm -f ./part.mount
			done < ./disk.part.tmp
		fi
		rm -f ./disk.part
		rm -f ./disk.part.tmp
	done < ./fdisk.log

	rm -f ./mounts
	rm -f ./fdisk.log
}

try_to_mount_all_disk()
{
	fdisk -l | grep -E -o '/dev/nvme[0-9]n[0-9]:|/dev/sd[a-z]:' | cut -d : -f 1 > ./fdisk.log

	while read line
	do
		fdisk -l $line | grep "^$line" > ./disk.part
		if [ $? -eq 1 ]; then
			# There is no partition in the disk
			rm -f ./disk.part
			mount | grep "$line" > /dev/null
			if [ $? -eq 1 ]; then
				#The disk was not mounted
				dir_name=`echo "$line" | cut -d / -f 3`
				mkdir /tmp/$dir_name
				mount "$line" /tmp/$dir_name
				if [ $? -eq 1 ]; then
					#mkfs.ext4 for the disk
					mkfs.ext4 $line
					mount "$line" /tmp/$dir_name
				else
					continue
				fi
			else
				#The disk was mounted
				continue
			fi
		else
			# There is/are some partitions in the disk
			cat ./disk.part | awk -F " " '{print $1}' > ./disk.part.tmp
			while read PART
			do
				mount | grep "$PART" > /dev/null
				if [ $? -eq 1 ]; then
					#The partition was not mounted
					cat ./disk.part | grep $PART | grep "Extended" > /dev/null
					if [ $? -eq 1 ]; then
						file -s $PART
						dir_name=`echo "$PART" | cut -d / -f 3`
						mkdir /tmp/$dir_name
						mount "$line" /tmp/$dir_name
						if [ $? -eq 1 ]; then
							#mkfs.ext4 for the partition
							mkfs.ext4 $line
							mount "$line" /tmp/$dir_name
						else
							continue
						fi
					else
						#The partition is Extended, ignore it
						continue
					fi
				else
					#The partition was mounted
					continue
				fi
			done < ./disk.part.tmp
			rm -f ./disk.part
			rm -f ./disk.part.tmp
		fi
	done < ./fdisk.log
	rm -f ./fdisk.log
}

cpu_stress_test
memory_stress_test
io_stress_test
disk_stress_test
