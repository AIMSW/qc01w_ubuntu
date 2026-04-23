#!/bin/bash
#set -x

init_env()
{
  export UBUNTU_ISO_URL=https://people.canonical.com/~platform/images/qualcomm-iot/ubuntu-24.04/ubuntu-24.04-x09/ubuntu-desktop-24.04/iot-qualcomm-dragonwing-classic-desktop-2404-x09-20260306.4096b.img.xz
  export UBUNTU_ISO=$(basename "$UBUNTU_ISO_URL")
  export UBUNTU_img="${UBUNTU_ISO%.xz}"

  #export UBUNTU_manifest_URL=https://people.canonical.com/~platform/images/qualcomm-iot/ubuntu-24.04/ubuntu-24.04-x09/ubuntu-desktop-24.04/iot-qualcomm-dragonwing-classic-desktop-2404-x09-20260306.4096b.manifest
  #export UBUNTU_manifest=$(basename "$UBUNTU_manifest_URL")
  export UBUNTU_rawprogram0_URL=https://people.canonical.com/~platform/images/qualcomm-iot/ubuntu-24.04/ubuntu-24.04-x09/ubuntu-desktop-24.04/rawprogram0.xml
  export UBUNTU_rawprogram0=$(basename "$UBUNTU_rawprogram0_URL")
  #export UBUNTU_dtb_URL=https://people.canonical.com/~platform/images/qualcomm-iot/ubuntu-24.04/ubuntu-24.04-x09/ubuntu-desktop-24.04/dtb.bin
  #export UBUNTU_dtb=$(basename "$UBUNTU_dtb_URL")
  export UBUNTU_SHA_URL=https://people.canonical.com/~platform/images/qualcomm-iot/ubuntu-24.04/ubuntu-24.04-x09/ubuntu-desktop-24.04/SHA256SUMS
  export UBUNTU_SHA=$(basename "$UBUNTU_SHA_URL")

  export QC01W_UBUNTU_VERSION=1068.71.qc01w

  export QC01W_BOOT_FIRMWARE_BASE_URL=https://github.com/AIMSW/qc01w_boot_firmware/releases/download
  export QC01W_BOOT_FIRMWARE_URL=$QC01W_BOOT_FIRMWARE_BASE_URL/$QC01W_UBUNTU_VERSION/Release.tar.gz
  export QC01W_BOOT_FIRMWARE_SHA_URL=$QC01W_BOOT_FIRMWARE_BASE_URL/$QC01W_UBUNTU_VERSION/SHA256SUM
  export QC01W_BOOT_FIRMWARE_SHA=$(basename "$QC01W_BOOT_FIRMWARE_SHA_URL")

  export DOWNLOAD_ISO=0
  export CHECK_SHA=0

  export workfolder=.repack
  mkdir -p $workfolder

  export rootfs_folder=$PWD/../../rootfs
  export deb_folder=$PWD/../../rootfs/var/qc01w/deb

  export nhlos_bins_folder=
  export rootfs_folder=
  export dtb_folder=
  export script_folder=

  export SUDOPW=
  export dev=
}

check_sha() {
  #$1 file_name
  #$2 SHA256SUM
  grep "$1" "$2" | sha256sum -c - >/dev/null 2>&1
}

download_file()
{
  #$1 file name URL
  local_file_name=$(basename "$1")

  #2 SHA256SUM

  for i in {1..3}; do
    if [ ! -f $local_file_name ]; then
      echo download $local_file_name
      curl -LO $1
    else
      if ! check_sha $local_file_name $2 && [ $CHECK_SHA == "1" ]; then
        echo "$local_file_name SHA fail, redownload"
        rm $local_file_name
        curl -LO $1
     else
       if [ "$CHECK_SHA" == "1" ]; then
         echo "$local_file_name SHA pass"
       else
         echo "$local_file_name exists, but SHA was not checked"
       fi
       break;
     fi
    fi
  done
}

download_boot_firmware()
{
  mkdir -p boot_firmware
  pushd boot_firmware

  curl -LO $QC01W_BOOT_FIRMWARE_SHA_URL

  CHECK_SHA=1
  download_file $QC01W_BOOT_FIRMWARE_URL $QC01W_BOOT_FIRMWARE_SHA

  tar zxvf $(basename "$QC01W_BOOT_FIRMWARE_URL")

  nhlos_bins_folder=$PWD/Release/nhlos-bins
  rootfs_folder=$PWD/Release/rootfs
  dtb_folder=$PWD/Release/dtb
  script_folder=$PWD/Release/script

  popd
}

download_ubuntu_iso()
{
  if [ "$DOWNLOAD_ISO" == "1"  ]; then
    if [ "$CHECK_SHA" == "1" ]; then
      curl -O $UBUNTU_SHA_URL
    fi

    download_file $UBUNTU_ISO_URL $UBUNTU_SHA
    download_file $UBUNTU_manifest_URL $UBUNTU_SHA
    download_file $UBUNTU_rawprogram0_URL $UBUNTU_SHA
    download_file $UBUNTU_dtb_URL $UBUNTU_SHA

    unxz -k $UBUNTU_ISO
  fi
}

mount_ubuntu_iso()
{
  #echo $SUDOPW | sudo -S echo;
  export dev="$(sudo -S losetup --sector-size=4096 --find --show --partscan $UBUNTU_img)"

  sudo -S partprobe ${dev}
  mkdir -p mnt
  sudo mount "${dev}p3" mnt/
  sudo mount "${dev}p1" mnt/boot/efi

  if [ $? -eq 0 ]; then
      echo "Mount successfully ISO on $dev."
  else
      echo "Command failed with exit status $?"
      exit 1
  fi
}

umount_ubuntu_iso()
{
  SEARCH_STRING="iot-qualcomm-dragonwing-classic"

  losetup --list --noheadings -O NAME,BACK-FILE | while read device backing_file; do
    if [[ "$backing_file" == *"$SEARCH_STRING"* ]]; then
        echo "Found '$SEARCH_STRING' in the string."
        sudo umount -R mnt
        rmdir mnt
        sudo losetup -d "${device}"
    fi
  done

  if [ $? -eq 0 ]; then
      echo "UnMount successfully ISO on $dev."
  else
      echo "Command failed with exit status $?"
      exit 1
  fi
}

patch_cmd_line()
{
  echo "patch_cmd_line"

  pushd mnt/etc/default/grub.d >/dev/null 2>&1
  sudo -S cp 99-qcom-iot-defaults.cfg 99-qcom-iot-defaults.cfg_org
  sudo -S sed -i 's|console=ttyMSM0,115200n8 |console=ttyMSM0,115200n8 dwc.pci=blacklist_bdf=0x208 firmware_class.path=\"/etc\" |' 99-qcom-iot-defaults.cfg
  popd >/dev/null 2>&1

  pushd mnt/boot/grub >/dev/null 2>&1
  sudo -S cp grub.cfg grub.cfg_org
  sudo -S sed -i 's|console=ttyMSM0,115200n8 |console=ttyMSM0,115200n8 dwc.pci=blacklist_bdf=0x208 firmware_class.path=\"/etc\" |' grub.cfg
  popd >/dev/null 2>&1
}

cp_rootfs_into_iso()
{
  echo "cp_rootfs_into_iso"

  pushd mnt >/dev/null 2>&1
  sudo rm var/qc01w/deb/linux-*.deb
  sudo -S cp -r $rootfs_folder/* .

  popd >/dev/null 2>&1
}

just_umount_iso()
{
  init_env
  pushd $workfolder >/dev/null 2>&1

  umount_ubuntu_iso

  popd >/dev/null 2>&1
}

gen_release()
{
  mkdir -p Release
  pushd Release
  
  cp -r $nhlos_bins_folder/* .
  cp -r $dtb_folder/* .
  cp -r $script_folder/* .
  cp ../$workfolder/$UBUNTU_img .
  cp ../$workfolder/$UBUNTU_rawprogram0 .
  popd
}

repack_main()
{
  init_env
  pushd $workfolder >/dev/null 2>&1
  sudo echo

  download_ubuntu_iso
  download_boot_firmware

  mount_ubuntu_iso

  patch_cmd_line
  #enable_service
  cp_rootfs_into_iso

  #read -n 1 -s -r -p "Press any key to continue..."

  umount_ubuntu_iso

  popd >/dev/null 2>&1
  
  gen_release
}

repack_main