#!/bin/sh
#
# Flash ESP32-S3 Linux (16MB flash / 8MB PSRAM N16R8) — full image set.
#
# Usage:  ./flash.sh <serial-port> [baud]
#   e.g.  ./flash.sh /dev/ttyUSB0 921600
#         ./flash.sh /dev/cu.usbmodem1101 921600
#
# First install on a device: uncomment the erase_flash line below (or run it
# manually) to wipe stale NVS/OTA data, then run this script.
#
# Requires: python3 -m pip install esptool
#
PORT="${1:?usage: flash.sh <serial-port> [baud]}"
BAUD="${2:-921600}"

# esptool.py --chip esp32s3 --port "$PORT" erase_flash

esptool.py --chip esp32s3 --port "$PORT" --baud "$BAUD" write_flash \
	0x00000  bootloader.bin \
	0x08000  partition-table.bin \
	0x10000  network_adapter.bin \
	0xb0000  etc.jffs2 \
	0x120000 xipImage \
	0x600000 rootfs.cramfs
