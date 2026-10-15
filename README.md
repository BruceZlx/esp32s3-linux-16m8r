# ESP32-S3 Linux — 16MB Flash / 8MB PSRAM (N16R8) 构建工程

[English version below](#english)

基于 [jcmvbkbc/esp32-linux-build](https://github.com/jcmvbkbc/esp32-linux-build)
（commit `92e07a0`）的 `rebuild-esp32s3-linux-wifi.sh` 改造的 CI 构建，
目标硬件为 **16MB Flash + 8MB Octal PSRAM** 的 ESP32-S3 模组
（N16R8，如 ESP32-S3-DevKitC-1-N16R8）。

上游自带的两个配置是 8M Flash/8M PSRAM（devkit-c1-8m）和 16M/16M（box3），
本仓库是两者的组合：**16MB 分区表 + 8MB PSRAM 内存布局**。

## 组成

| 文件 | 作用 |
|---|---|
| `ci-build.sh` | 无烧录版一键构建：crosstool-NG 工具链 → buildroot(内核+rootfs) → esp-hosted(WiFi 固件+引导) |
| `sdkconfig.defaults.esp32s3.16n8r` | esp-hosted/ESP-IDF 配置：16MB Flash、`partition_table.esp32s3.16m`、`LINUX_PSRAM_8M` |
| `flash.sh` | 产物烧录脚本（随 dist 一起打包） |

内核/rootfs 复用上游 buildroot（分支 `xtensa-2025.08-fdpic`，2025-11 更新到
Linux 6.16）的配置 `esp32s3_devkit_c1_8m_defconfig`
（内核数据段按 8MB PSRAM 布局在 `0x3d800000`，DTB 为 `esp32s3-devkit-c1`）；
Flash 大小只由 esp-hosted 侧 sdkconfig 与分区表决定，与 buildroot 无关。

## 产物（Actions artifact `esp32s3-linux-16m8r-dist`）

| 文件 | 烧录偏移 | 说明 |
|---|---|---|
| `bootloader.bin` | 0x00000 | ESP-IDF 二级 bootloader |
| `partition-table.bin` | 0x08000 | 16MB flash 分区表 |
| `network_adapter.bin` | 0x10000 | esp-hosted 固件（CPU1 上的 WiFi 协处理器 + Linux 加载器） |
| `etc.jffs2` | 0xb0000 | 可写 /etc 分区（wpa_supplicant 配置等） |
| `xipImage` | 0x120000 | Linux 6.16 内核（XIP，片上执行） |
| `rootfs.cramfs` | 0x600000 | 根文件系统（XIP cramfs） |

## 烧录与使用

```sh
python3 -m pip install esptool
python3 -m esptool --chip esp32s3 --port <串口> erase_flash   # 首次烧录先全片擦除
./flash.sh <串口> 921600
```

串口监视 115200（UART0 与 USB-Serial-JTAG 口均有控制台输出），
`root` 空密码直接登录；SSH（dropbear）默认拒绝空密码，先在控制台 `passwd` 设置。
WiFi：编辑 `/etc/wpa_supplicant.conf` 后 `wpa_cli -i wlan0 reconfigure`。

## 本地构建（任意 Debian/Ubuntu）

与 CI 相同：

```sh
sudo apt install autoconf automake bash bc bison build-essential cmake flex \
  gawk git gperf help2man libncurses-dev libtool libtool-bin libusb-1.0-0 \
  python3 python3-venv rsync texinfo unzip wget
bash ci-build.sh    # 产物在 dist/
```

---

# English

# ESP32-S3 Linux build — 16MB Flash / 8MB PSRAM (N16R8)

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
