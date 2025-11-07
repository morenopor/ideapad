# Lenovo Ideapad Hardware Profile

This document captures the key hardware details for the Lenovo Ideapad development laptop.

## CPU
- **Model:** Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz (8 threads, 4 cores)
- **Architecture:** x86_64 (supports 32-bit and 64-bit modes)
- **Base/Max Frequency:** 1.60 GHz base, up to 3.40 GHz boost
- **Virtualization:** Intel VT-x
- **Instruction Extensions:** SSE up to SSE4.2, AVX, AVX2, AES, FMA, BMI1/BMI2, and more (see `Flags`)
- **Caches:**
  - L1d: 128 KiB (4x 32 KiB per core)
  - L1i: 128 KiB (4x 32 KiB per core)
  - L2: 1 MiB (4x 256 KiB per core)
  - L3: 6 MiB shared
- **Mitigations:** CPU microcode mitigations in place for vulnerabilities including Spectre, Meltdown, L1TF, MDS, Retbleed, and more.

## Memory
- **Installed Modules:** 4 GB + 16 GB (total 20 GB)

## Graphics
- **Integrated GPU:** Intel UHD Graphics 620 (i915 driver)
- **Discrete GPU:** NVIDIA GeForce GTX 1050 Mobile (nvidia driver)

## Storage
- **NVMe SSD:** Kingston A2000 500 GB (model `KINGSTON SA2000M8500G`)
- **HDD:** Seagate ST2000LX001-1RG1 2 TB (512e / 4K physical sectors)

## Networking
- **Wireless:** Qualcomm Atheros QCA9377 802.11ac (ath10k_pci driver)

## Software
- **Kernel:** 6.8.0-60-generic
- **Distribution:** Ubuntu 24.04.2 LTS (Noble) with GNOME desktop

