#!/bin/bash
#
# Non-interactive CI variant of jcmvbkbc/esp32-linux-build's rebuild-esp32s3-linux-wifi.sh
# (https://github.com/jcmvbkbc/esp32-linux-build @ 92e07a0)
#
# Target: ESP32-S3 with 16MB FLASH + 8MB PSRAM (octal), e.g. N16R8 modules
#         (ESP32-S3-DevKitC-1-N16R8 and most N16R8 boards).
#
# Differences from the upstream script:
#   - never flashes / never prompts; stops after building
#   - reuses upstream buildroot config esp32s3_devkit_c1_8m (kernel is laid out
#     for 8MB PSRAM: XIP_DATA_ADDR=0x3d800000, DTB esp32s3-devkit-c1);
#     flash size is handled by the esp-hosted sdkconfig + partition table
#   - uses sdkconfig.defaults.esp32s3.16n8r: 16MB flash, partition_table.esp32s3.16m,
#     LINUX_PSRAM_8M=y (same as base), i.e. the 16MB-flash counterpart of the
#     stock 8MB devkit-c1 config
#   - esp-idf tools installed for esp32s3 only (saves ~2GB disk)
#   - collects all flashable images into dist/
#
set -e
set -o pipefail

ROOT="${ROOT:-$PWD}"                 # this repo checkout
WORK="${WORK:-$ROOT/build}"          # heavy build tree (caller puts it on a big disk)
mkdir -p "$WORK"
DIST="$ROOT/dist"
LOGS="$ROOT/logs"

CTNG_VER=xtensa-fdpic
CTNG_CONFIG=xtensa-esp32s3-linux-uclibcfdpic
BUILDROOT_VER=xtensa-2024.08-fdpic
ESP_HOSTED_VER=ipc-5.1.1
ESP_HOSTED_CONFIG=sdkconfig.defaults.esp32s3.16n8r
BUILDROOT_CONFIG=esp32s3_devkit_c1_8m

mkdir -p "$WORK" "$DIST" "$LOGS"
echo "== host: $(uname -a), nproc=$(nproc) =="
df -h "$WORK" "$ROOT"

# run a long build step, keep its full log in a file, show tail on failure
run_logged() {
	local name="$1"; shift
	echo "== [$(date +%H:%M:%S)] $name =="
	if "$@" >"$LOGS/$name.log" 2>&1; then
		tail -n 3 "$LOGS/$name.log"
	else
		local rc=$?
		echo "!! $name FAILED (rc=$rc), last 200 lines:"
		tail -n 200 "$LOGS/$name.log"
		exit $rc
	fi
}

cd "$WORK"

#
# autoconf 2.71 (same as upstream)
#
if [ ! -d autoconf-2.71/root/bin ] ; then
	wget -q https://ftp.gnu.org/gnu/autoconf/autoconf-2.71.tar.xz
	tar -xf autoconf-2.71.tar.xz
	run_logged autoconf-build bash -c 'cd autoconf-2.71 && ./configure --prefix="$PWD/root" && make && make install'
fi
export PATH="$WORK/autoconf-2.71/root/bin:$PATH"

#
# dynconfig
#
if [ ! -f xtensa-dynconfig/esp32s3.so ] ; then
	git clone -q https://github.com/jcmvbkbc/xtensa-dynconfig -b original
	git clone -q https://github.com/jcmvbkbc/config-esp32s3 esp32s3
	run_logged dynconfig make -C xtensa-dynconfig ORIG=1 CONF_DIR="$WORK" esp32s3.so
fi
export XTENSA_GNU_CONFIG="$WORK/xtensa-dynconfig/esp32s3.so" # must be set for everything touching the toolchain

#
# toolchain (crosstool-NG)
#
if [ ! -x crosstool-NG/builds/xtensa-esp32s3-linux-uclibcfdpic/bin/xtensa-esp32s3-linux-uclibcfdpic-gcc ] ; then
	git clone -q https://github.com/jcmvbkbc/crosstool-NG.git -b $CTNG_VER
	run_logged ctng-make bash -c 'cd crosstool-NG && ./bootstrap && ./configure --enable-local && make'
	( cd crosstool-NG && ./ct-ng $CTNG_CONFIG )
	run_logged ctng-build bash -c 'cd crosstool-NG && CT_PREFIX="$PWD/builds" nice ./ct-ng build'
	[ -x crosstool-NG/builds/xtensa-esp32s3-linux-uclibcfdpic/bin/xtensa-esp32s3-linux-uclibcfdpic-gcc ]
	rm -rf crosstool-NG/.build   # build temp, several GB; final toolchain stays in builds/
fi
TOOLCHAIN="$WORK/crosstool-NG/builds/xtensa-esp32s3-linux-uclibcfdpic"

#
# kernel + rootfs (buildroot)
#
if [ ! -d buildroot ] ; then
	git clone -q https://github.com/jcmvbkbc/buildroot -b $BUILDROOT_VER
else
	git -C buildroot pull -q || true
fi
if [ ! -d build-buildroot-$BUILDROOT_CONFIG ] ; then
	make -C buildroot O="$WORK/build-buildroot-$BUILDROOT_CONFIG" ${BUILDROOT_CONFIG}_defconfig
	buildroot/utils/config --file build-buildroot-$BUILDROOT_CONFIG/.config --set-str TOOLCHAIN_EXTERNAL_PATH "$TOOLCHAIN"
	buildroot/utils/config --file build-buildroot-$BUILDROOT_CONFIG/.config --set-str TOOLCHAIN_EXTERNAL_PREFIX '$(ARCH)-esp32s3-linux-uclibcfdpic'
	buildroot/utils/config --file build-buildroot-$BUILDROOT_CONFIG/.config --set-str TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX '$(ARCH)-esp32s3-linux-uclibcfdpic'
fi
run_logged buildroot make -C buildroot O="$WORK/build-buildroot-$BUILDROOT_CONFIG"
IMAGES="$WORK/build-buildroot-$BUILDROOT_CONFIG/images"
[ -f "$IMAGES/xipImage" -a -f "$IMAGES/rootfs.cramfs" -a -f "$IMAGES/etc.jffs2" ] || { echo "buildroot images missing"; ls -la "$IMAGES"; exit 1; }

#
# bootloader + wifi coprocessor firmware (esp-hosted on esp-idf)
#
[ -d esp-hosted ] || git clone -q https://github.com/jcmvbkbc/esp-hosted -b $ESP_HOSTED_VER
export IDF_TOOLS_PATH="$WORK/idf-tools"
pushd esp-hosted/esp_hosted_ng/esp/esp_driver
# upstream's `cmake .` inits submodules, runs esp-idf install.sh and replaces
# esp_wifi libs; restrict toolchain install to esp32s3 to save disk/time
sed -i '/install.sh$/s/$/ esp32s3/' CMakeLists.txt
run_logged esp-hosted-setup cmake .
cd esp-idf
. export.sh
cd ../network_adapter
run_logged idf-set-target idf.py set-target esp32s3
cp "$ROOT/$ESP_HOSTED_CONFIG" sdkconfig
run_logged idf-build idf.py build
APP="$PWD/build"
popd

#
# package everything flashable
#
cp "$APP/bootloader/bootloader.bin"        "$DIST/"
cp "$APP/partition_table/partition-table.bin" "$DIST/"
cp "$APP/network_adapter.bin"              "$DIST/"
cp "$IMAGES/xipImage"  "$DIST/"
cp "$IMAGES/rootfs.cramfs" "$DIST/"
cp "$IMAGES/etc.jffs2" "$DIST/"
cp "$ROOT/flash.sh" "$DIST/"
ls -la "$DIST"
echo "== BUILD DONE =="
