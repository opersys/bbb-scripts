#!/bin/bash

function version_gt() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"; }

# Format an SD card for Android on BeagelBone Black

if [ $# -ne 1 ]; then
        echo "Usage: $0 [drive]"
        echo "       drive is 'sdb', 'mmcblk0'"
        exit 1
fi

DRIVE=$1

# Check the drive exists in /sys/block
if [ ! -e /sys/block/${DRIVE}/size ]; then
	echo "Drive does not exist"
	exit 1
fi

# Check it is a flash drive (size < 32MiB)
NUM_SECTORS=`cat /sys/block/${DRIVE}/size`
if [ $NUM_SECTORS -eq 0 -o $NUM_SECTORS -gt 64000000 ]; then
	echo "Does not look like an SD card, bailing out"
	exit 1
fi

# Unmount any partitions that have been automounted
if [ $DRIVE == "mmcblk0" ]; then
	sudo umount /dev/${DRIVE}*
	BOOT_PART=/dev/${DRIVE}p1
	SYSTEM_PART=/dev/${DRIVE}p2
	USER_PART=/dev/${DRIVE}p3
	CACHE_PART=/dev/${DRIVE}p4
else
	sudo umount /dev/${DRIVE}[1-9]
	BOOT_PART=/dev/${DRIVE}1
	SYSTEM_PART=/dev/${DRIVE}2
	USER_PART=/dev/${DRIVE}3
	CACHE_PART=/dev/${DRIVE}4
fi

set -e

# Overwite existing partiton table with zeros
sudo dd if=/dev/zero of=/dev/${DRIVE} bs=1M count=10
if [ $? -ne 0 ]; then echo "Error: dd"; exit 1; fi

# Create 5 primary partitons on the sd card
#  1: boot:   FAT32, 64 MiB, boot flag
#  2: system: Linux, 1024 MiB
#  3: data:   Linux, 3072 MiB
#  4: cache:  Linux, 256 MiB
#  5: vendor: Linux, 10 MiB

# Note that the formatting of parameters changed slightly v2.26
SFDISK_VERSION=`sfdisk --version | awk '{print $4}'`
if version_gt $SFDISK_VERSION "2.26"; then
     echo "sfdisk uses new syntax"
	sudo sfdisk --force /dev/${DRIVE} << EOF
,64M,0x0C,*,
,1024M,,,
,2048M,,,
,256M,,,
EOF
else
	sudo sfdisk --force --unit M /dev/${DRIVE} << EOF
,64,0x0c,*
,1024,,,
,2048,,,
,256,,,
EOF
fi
if [ $? -ne 0 ]; then echo "Error: sdfisk"; exit 1; fi

sudo mkfs.vfat -nboot ${BOOT_PART}
if [ $? -ne 0 ]; then echo "Error: mkfs.ext4"; exit 1; fi

# Copy boot files
echo "Mounting $BOOT_PART"
sudo mount $BOOT_PART /mnt
if [ $? != 0 ]; then echo "ERROR"; exit; fi

UNAME=4.19.59-bone36

sudo mkdir -p /mnt/boot/dtbs/$UNAME

mkimage -A arm -O linux -T ramdisk -d ${ANDROID_PRODUCT_OUT}/ramdisk.img uRamdisk
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo cp external/u-boot/MLO /mnt
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo cp external/u-boot/u-boot.img /mnt
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo cp uRamdisk /mnt/boot/initrd.img-$UNAME
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo cp ${ANDROID_PRODUCT_OUT}/uEnv.txt /mnt/boot/
sudo mkenvimage -s 1024 -o/mnt/boot/uboot.env ${ANDROID_PRODUCT_OUT}/uEnv.txt
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo cp $ANDROID_PRODUCT_OUT/am335x-boneblack-android.dtb /mnt/boot/dtbs/$UNAME
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo cp $ANDROID_PRODUCT_OUT/zImage /mnt/boot/vmlinuz-$UNAME
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo umount /mnt

# Copy disk images

echo "Writing system"
sudo dd if=${ANDROID_PRODUCT_OUT}/system.img of=$SYSTEM_PART bs=1M status=progress && sync
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo e2label $SYSTEM_PART system

echo "Writing userdata (takes a long time)"
sudo dd if=${ANDROID_PRODUCT_OUT}/userdata.img of=$USER_PART bs=1M status=progress && sync
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo e2label $USER_PART userdata

echo "Writing cache"
sudo dd if=${ANDROID_PRODUCT_OUT}/cache.img of=$CACHE_PART bs=1M status=progress && sync
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo e2label $CACHE_PART cache

echo "SUCCESS! Android4Beagle installed on the uSD card. Enjoy"

exit 0
