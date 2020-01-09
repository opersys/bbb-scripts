#!/bin/bash

DEVICE_DIR=device/beagleboard/beagleboneblack

# The number of CPU cores to use for Android compilation. Default is
# all of them, but you can override by setting CORES
if [ -z $CORES ]; then
	CORES=$(getconf _NPROCESSORS_ONLN)
fi

if [ -z $ANDROID_BUILD_TOP ]; then
	echo "Please 'source build/envsetup.sh' and run 'lunch' first"
	exit
fi

if [ $TARGET_PRODUCT != "beagleboneblack" -a $TARGET_PRODUCT != "beagleboneblack_sd" ]; then
	echo "Please select product beagleboneblack or beagleboneblack_sd"
	exit
fi

#echo "Building $TARGET_PRODUCT using $CORES cpu cores"
#echo ""
#echo "Building kernel"
#cd $ANDROID_BUILD_TOP/bb-kernel
#if [ $? != 0 ]; then echo "ERROR"; exit; fi

AUTO_BUILD=1 ./build_kernel.sh
if [ $? != 0 ]; then echo "ERROR"; exit; fi

# Merge an overlay for the fstab. This works around the lack of DTBO.
rm -v am335x-boneblack-android.dtb
(cat KERNEL/arch/arm/boot/dts/am335x-boneblack.dts && \
     echo "#include \"../device/beagleboard/beagleboneblack/dts/$TARGET_PRODUCT.dts\"" ) | \
    cpp -x assembler-with-cpp -E -undef -nostdinc -IKERNEL/include -IKERNEL/arch/arm/boot/dts | \
    KERNEL/scripts/dtc/dtc -O dtb -@ --include KERNEL/arch/arm/boot/dts \
        -Wno-unit_address_vs_reg \
        -Wno-unit_address_format \
        -Wno-avoid_unnecessary_addr_size \
        -Wno-alias_paths \
        -Wno-graph_child_address \
        -Wno-graph_port \
        -Wno-unique_unit_address \
        -Wno-pci_device_reg \
        -o am335x-boneblack-android.dtb

# Append the dtb to zImage because the Android build doesn't know about dtbs
cat KERNEL/arch/arm/boot/zImage am335x-boneblack-android.dtb > ../zImage-dtb
if [ $? != 0 ]; then echo "ERROR"; exit; fi
cp ../zImage-dtb $ANDROID_BUILD_TOP/$DEVICE_DIR

# Grab all the kernel modules
mkdir $ANDROID_BUILD_TOP/$DEVICE_DIR/modules
MODULES=`find -name "*.ko"`
for f in $MODULES; do
	cp $f $ANDROID_BUILD_TOP/$DEVICE_DIR/modules/`basename $f`
	if [ $? != 0 ]; then echo "ERROR"; exit; fi
done

echo "Building U-Boot"
cd $ANDROID_BUILD_TOP/u-boot
# The Android prebuilt gcc fails to build U-Boot, so use the Linaro gcc which
# was installed to build the ti-kernel
CC=/home/neumann/Android/Transtex/9.0-BeagleBone/bb-kernel/dl/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-
make CROSS_COMPILE=$CC am335x_evm_config
if [ $? != 0 ]; then echo "ERROR"; exit; fi
make CROSS_COMPILE=$CC
if [ $? != 0 ]; then echo "ERROR"; exit; fi
cd $ANDROID_BUILD_TOP

echo "Building Android"

make -j${CORES}
if [ $? != 0 ]; then echo "ERROR"; exit; fi

echo "SUCCESS! Everything built for $TARGET_PRODUCT"
