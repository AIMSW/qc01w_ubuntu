# Embedded Image Generation Tool

A lightweight, automated script designed to generate full, flashable system images for QC01W. This tool streamlines the ISO image downloading from internet, and packaging phases into a single deployment pipeline.

---

## 🚀 Features

* **Essential Binaries download:** Include NonHLOS and Ubuntu IOT ISO image.
* **Custom RootFS Support:** Seamlessly integrates custom root filesystems for QC01W hardware.
* **Flash-Ready Output:** Generates a full image pack works with burn batch(_Burn_Image_AIBO.bat).

---

## 🛠️ Prerequisites

This toolchain utilizes a cross-platform deployment workflow: the image is **generated on Linux** and **flashed via Windows**.
```
┌─────────────────────────┐               ┌─────────────────────────┐
│  Ubuntu Host Machine    │               │  Windows Host Machine   │
│                         │  Copy Image   │                         │
│  1. Run script          │ ------------> │  1. Enter EDL mode      │
│  2. Output full IMG Pack│               │  2. Run *.bat to update │
└─────────────────────────┘               └─────────────────────────┘

```

### 1. Generation Host (Ubuntu Environment)
The generation script must be executed on an **Ubuntu** system (or an Ubuntu-based container/VM) to handle Linux filesystem creation and loop device mounting.

* **Dependencies:** Install the required system utilities before running the script:
```bash
  N/A
```

- **Privileges:** `sudo` access is required for loop device configuration (`losetup`), partition mapping.

### 2. Flashing Host (Windows Environment)

Once the image directory (e.g., `Release`) is built, transfer it to a **Windows machine** for the download phase.

---

## 📦 Usage

### 1. Download and run the script

Execute the generation script

Bash

```
./repack.sh
```
or
```bash
./repack.sh 2>&1 | tee repack.log
```
## 💡 Key Highlights

> [!NOTICE]
>
> ### 📌 Custom Developer Guidelines
>
> - **[1]:** _You will be asked to input password several times in generation phase._
>     

## 💾 Flashing the Target Device

Once the image creation is complete, the final binary will be located in the `Release` directory. You can flash it directly to your QC01W using `_Burn_Image_AIBO.bat`
