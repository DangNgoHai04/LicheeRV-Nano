# LicheeRV-Nano Build System

Embedded Linux (Buildroot) build system for the **LicheeRV Nano** board (Sophgo SG2002/CV181x, RISC-V architecture), forked and customized for personal/company projects on this platform — including an AI camera pipeline, RTSP streaming, and inference samples using the TDL SDK.


## About the board

- Target board: **LicheeRV Nano** (Sophgo SG2002/CV181x SoC, RISC-V)
- Build system: Buildroot

The **SG2002** is Sophgo's dual-core SoC combining a RISC-V application core (running Linux) with a lightweight RTOS core, plus an integrated NPU for on-device AI inference — making it well suited for low-power edge vision applications like camera-based AI detection.

## Changes from upstream

- Updated submodule URLs and fork management workflow
- Adjusted `.gitignore` so vendor prebuilt binaries (`.a`/`.so`) don't get silently dropped
- Resolved nested submodule paths (e.g. `freertos → Source → FreeRTOS-Plus-POSIX`)
- Added utility scripts: `add_submodules.sh`, `update_submodules.sh`, `clean_branches.sh`
- Documented the full build pipeline (U-Boot/FSBL, panel FIP generation, temporary DTS edits) in `build-licheervnano.sh` / `prepare-licheesgnano.sh`

## Compatibility

Works with boards based on the Sophgo CV181x/SG200x SoC family, including:

- Sipeed LicheeRV Nano (primary target of this repo)
- MilkV Duo256/DuoS
- Sipeed NanoKVM (Cube, Lite, PCIe)

## Requirements

- OS: Debian 11 / Ubuntu 22.04 or later
- CPU: x86_64 (AMD/Intel)
- RAM: at least 8GB (needed to build OpenCV tests); other components can be built with 4GB
- Disk space: at least 30GB free (plus ~40GB if building the toolchain from source)

## Getting Started

### Clone the repository

```bash
git clone https://github.com/DangNgoHai04/LicheeRV-Nano 
cd LicheeRV-Nano
git submodule update --init --recursive 
```

### Install dependencies

```bash
./host/prepare-host.sh
```

### Build

```bash
./build-licheervnano.sh
```


## Main Submodules
- buildroot = Core build framework, automates building the embedded linux os
- fsbl = First Stage Boot Loader
- linux_5.10 = The Linux kernel source
- middleware = Sophgo's media processing SDK for camera/AI pipelines
- opensbi = OpenSBI - standard RISC-V 
- osdrv = Sophgo-specific OS drivers/modules not included in the mainline kernel
- tdl_sdk = AI inference SDK for running models on the SG2002's built-in NPU
- u-boot-2021.10 = loads the kernel/rootfs

