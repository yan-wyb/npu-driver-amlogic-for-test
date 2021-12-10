#!/bin/bash

FENIX=$1
patchversion=$2

if [ -z $FENIX ]; then
	echo "usage: $0 <Fenix Repo> [patchversion]"
	exit
fi

ROOT=`pwd`
DDK_VERSION=`cat $ROOT/VERSION | grep "Release ID" | awk '{print $3}'`
TARGET_DIR="$ROOT/.temp"
LINUX_DIR="$FENIX/build/linux"
TOOLCHAIN_DIR="$FENIX/build/toolchains/gcc-linaro-aarch64-linux-gnu/bin/"
LINUX_VERSION_PROBED=`cat $LINUX_DIR/.config | grep "Linux/arm64" | awk '{print $3}'`


ARM_NPU_MODULE_DIR="kernel/amlogic/npu"
NPU_KO_INSTALL_DIR="$TARGET_DIR/lib/modules/$LINUX_VERSION_PROBED/kernel/amlogic/npu"
NPU_SO_INSTALL_DIR="$TARGET_DIR/lib"

ARM_NPU_DEP="$TARGET_DIR/lib/modules/$LINUX_VERSION_PROBED/modules.dep"

rm -rf $TARGET_DIR

version=${DDK_VERSION}
[ ! -z $patchversion ] && version=${DDK_VERSION}-${patchversion}

$ROOT/aml_buildroot.sh arm64 $LINUX_DIR $TOOLCHAIN_DIR

copy-arm-npu() {
	for m in `find $1 -path $TARGET_DIR -name "*.ko"`
	do
		[ ! -e $2 ] && mkdir $2 -p
		cp $m $2/ -rfa
		echo $4/`basename $m`: >> $3
	done
}

ARM_NPU_DEP_INSTALL_TARGET_CMDS() {
	copy-arm-npu $ROOT $NPU_KO_INSTALL_DIR $ARM_NPU_DEP $ARM_NPU_MODULE_DIR
}

NPU_INSTALL_TARGETS_CMDS() {
#	install -m 0755 $ROOT/build/sdk/drivers/galcore.ko $NPU_KO_INSTALL_DIR
	install -m 0755 $ROOT/sharelib/lib64/libGAL.so $NPU_SO_INSTALL_DIR
	install -m 0755 $ROOT/sharelib/lib64/* $NPU_SO_INSTALL_DIR
	install -m 0755 $ROOT/nnsdk/lib/lib64/libnnsdk.so $NPU_SO_INSTALL_DIR

	# Headers
	mkdir -p $TARGET_DIR/include
#	cp -r $ROOT/build/sdk/include $TARGET_DIR
	cp -r $ROOT/sdk/inc/CL $TARGET_DIR/include
	cp -r $ROOT/sdk/inc/VX $TARGET_DIR/include
	cp $ROOT/nnsdk/include/nn_sdk.h $TARGET_DIR/include
	cp $ROOT/nnsdk/include/nn_util.h $TARGET_DIR/include
	cp -r $ROOT/applib/ovxinc/include/* $TARGET_DIR/include
	# remove jpeg headers
	rm -rf $TARGET_DIR/include/jconfig.h
	rm -rf $TARGET_DIR/include/jmorecfg.h
	rm -rf $TARGET_DIR/include/jpeglib.h
}

NPU_INSTALL_TARGET_CMDS() {
#	mkdir -p $NPU_KO_INSTALL_DIR
	mkdir -p $NPU_SO_INSTALL_DIR
	NPU_INSTALL_TARGETS_CMDS
#	ARM_NPU_DEP_INSTALL_TARGET_CMDS
}

BUILD_DEB_PACKAGE() {
	local pkgname="aml-npu"
	local pkgdir=".tmp/${pkgname}_${version}_arm64"
	rm -rf $pkgdir
	mkdir -p $pkgdir/DEBIAN

	echo "Build NPU deb..."

	cat <<-EOF > $pkgdir/DEBIAN/control
	Package: $pkgname
	Version: ${version}
	Section: kernel
	Architecture: arm64
	Maintainer: Khadas <hello@khadas.com>
	Installed-Size: 1
	Priority: optional
	Depends: libjpeg9
	Description: Amlogic NPU libraries.
	EOF

	mkdir -p $pkgdir/lib $pkgdir/usr
	cp -arf $TARGET_DIR/lib $pkgdir
	cp -r $TARGET_DIR/include $pkgdir/usr

	# Create board deb file
	echo "Building package: $pkgname"
	fakeroot dpkg-deb -b $pkgdir ${pkgdir}.deb
	cp ${pkgdir}.deb $ROOT
	# Cleanup
	rm ${pkgdir}.deb
	rm -rf $pkgdir
}

NPU_INSTALL_TARGET_CMDS
BUILD_DEB_PACKAGE
