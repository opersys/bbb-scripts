#!/bin/bash

# The number of CPU cores to use for Android compilation. Default is
# all of them, but you can override by setting CORES
if [ -z $CORES ]; then
    CORES=$(getconf _NPROCESSORS_ONLN)
fi

if [ -z $ANDROID_BUILD_TOP ]; then
    echo "Please 'source build/envsetup.sh' and run 'lunch' first"
    exit
fi

if [ $TARGET_PRODUCT == "beagleboneblack_sd" -o $TARGET_PRODUCT == "beagleboneblack_emmc" ]; then
    DEVICE_DIR=device/beagleboard/beagleboneblack
else
    echo "Unknown TARGET_PRODUCT: $TARGET_PRODUCT"
    exit 1
fi

echo "Building $TARGET_PRODUCT using $CORES cpu cores"
echo ""
echo "Building kernel"
cd $ANDROID_BUILD_TOP/bb-kernel
if [ $? != 0 ]; then echo "ERROR"; exit; fi

AUTO_BUILD=1 ./build_kernel.sh
if [ $? != 0 ]; then echo "ERROR"; exit; fi

# Copy the kernel in OUT
cp KERNEL/arch/arm/boot/zImage $ANDROID_PRODUCT_OUT/zImage

# HACK: Merge an overlay for the fstab. This works around the lack of
# DTBO support
#
# TOOD: Use DTBO a partition! It would be better if we didn't have to
# do tis.
if [ -f $ANDROID_BUILD_TOP/$DEVICE_DIR/dts/$TARGET_PRODUCT.dts ]; then
    echo "Building DTB"
    
    rm -vf $ANDROID_PRODUCT_OUT/am335x-boneblack-android.dtb

    # This command was carefully worked out from kernel
    # sources. Please be cautious when changing this.
    (cat KERNEL/arch/arm/boot/dts/am335x-boneblack.dts && \
         echo "#include \"$ANDROID_BUILD_TOP/$DEVICE_DIR/dts/$TARGET_PRODUCT.dts\"" ) | \
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
                               -o $ANDROID_PRODUCT_OUT/am335x-boneblack-android.dtb

fi
    
##
## Build Android's U-Boot provided in external/u-boot
##

echo "Building U-Boot"
cd $ANDROID_BUILD_TOP/external/u-boot

# Use the GCC downloaded by the kernel script.
source $ANDROID_BUILD_TOP/bb-kernel/.CC

make CROSS_COMPILE=$CC am335x_evm_config
if [ $? != 0 ]; then echo "ERROR"; exit; fi

make CROSS_COMPILE=$CC
if [ $? != 0 ]; then echo "ERROR"; exit; fi

cd $ANDROID_BUILD_TOP

#
# Build Android sources.
# 

echo "Building Android"

make -j${CORES}
if [ $? != 0 ]; then echo "ERROR"; exit; fi

echo "SUCCESS! Everything built for $TARGET_PRODUCT"
