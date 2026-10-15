# ESP32-S3 Linux build — 16MB Flash / 8MB PSRAM (N16R8)

[简体中文](README.md) | **English**

A CI build derived from the `rebuild-esp32s3-linux-wifi.sh` script of
[jcmvbkbc/esp32-linux-build](https://github.com/jcmvbkbc/esp32-linux-build)
(commit `92e07a0`), targeting ESP32-S3 modules with **16MB flash + 8MB octal
PSRAM** (N16R8, e.g. ESP32-S3-DevKitC-1-N16R8).

Upstream ships two configurations — 8MB flash/8MB PSRAM (devkit-c1-8m) and
16MB/16MB (box3) — this repo combines them: **16MB partition table + 8MB PSRAM
kernel memory layout**.

## Layout

| File | Purpose |
|---|---|
| `ci-build.sh` | Non-flashing one-shot build: crosstool-NG toolchain → buildroot (kernel + rootfs) → esp-hosted (WiFi firmware + bootloader) |
| `sdkconfig.defaults.esp32s3.16n8r` | esp-hosted/ESP-IDF config: 16MB flash, `partition_table.esp32s3.16m`, `LINUX_PSRAM_8M` |
| `flash.sh` | Flash script for the produced images (shipped with dist) |

The kernel/rootfs reuse the upstream buildroot (branch `xtensa-2025.08-fdpic`,
updated to Linux 6.16 in 2025-11) configuration `esp32s3_devkit_c1_8m_defconfig`
(kernel data laid out for 8MB PSRAM at `0x3d800000`, DTB `esp32s3-devkit-c1`);
flash size is decided solely by the esp-hosted sdkconfig and partition table.

## Artifacts (Actions artifact `esp32s3-linux-16m8r-dist`)

| File | Flash offset | Description |
|---|---|---|
| `bootloader.bin` | 0x00000 | ESP-IDF second-stage bootloader |
| `partition-table.bin` | 0x08000 | 16MB flash partition table |
| `network_adapter.bin` | 0x10000 | esp-hosted firmware (WiFi coprocessor on the other CPU + Linux loader) |
| `etc.jffs2` | 0xb0000 | writable /etc partition (wpa_supplicant config etc.) |
| `xipImage` | 0x120000 | Linux 6.16 kernel (XIP — execute in place) |
| `rootfs.cramfs` | 0x600000 | root filesystem (XIP cramfs) |

## Flashing & usage

```sh
python3 -m pip install esptool
python3 -m esptool --chip esp32s3 --port <port> erase_flash   # full erase before first flash
./flash.sh <port> 921600
```

Serial console at 115200 (output on both UART0 and the USB-Serial-JTAG port);
log in as `root` with an **empty password**. SSH (dropbear) rejects empty
passwords by default — set one with `passwd` on the console first.
WiFi: edit `/etc/wpa_supplicant.conf`, then `wpa_cli -i wlan0 reconfigure`.

## Local build (any Debian/Ubuntu)

Same as CI:

```sh
sudo apt install autoconf automake bash bc bison build-essential cmake flex \
  gawk git gperf help2man libncurses-dev libtool libtool-bin libusb-1.0-0 \
  python3 python3-venv rsync texinfo unzip wget
bash ci-build.sh    # output lands in dist/
```
