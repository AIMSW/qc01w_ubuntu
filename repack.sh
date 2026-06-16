#!/bin/bash
#set -x

init_env()
{
  export UBUNTU_BASE_URL=https://people.canonical.com/~platform/images/qualcomm-iot/ubuntu-24.04/ubuntu-24.04-x10/ubuntu-desktop-24.04
  export UBUNTU_IMAGER_VERSION=iot-qualcomm-dragonwing-classic-desktop-2404-x10-20260403.4096b.img.xz

  export QC01W_UBUNTU_VERSION=1071.79.qc01w

  export UBUNTU_ISO_URL=$UBUNTU_BASE_URL/$UBUNTU_IMAGER_VERSION
  export UBUNTU_ISO=$(basename "$UBUNTU_ISO_URL")
  export UBUNTU_img="${UBUNTU_ISO%.xz}"
  export UBUNTU_rawprogram0_URL=$UBUNTU_BASE_URL/rawprogram0.xml
  export UBUNTU_rawprogram0=$(basename "$UBUNTU_rawprogram0_URL")
  export UBUNTU_dtb_URL=$UBUNTU_BASE_URL/dtb.bin
  export UBUNTU_dtb=$(basename "$UBUNTU_dtb_URL")
  export UBUNTU_SHA_URL=$UBUNTU_BASE_URL/SHA256SUMS
  export UBUNTU_SHA=$(basename "$UBUNTU_SHA_URL")

  export QC01W_BOOT_FIRMWARE_BASE_URL=https://github.com/AIMSW/qc01w_boot_firmware/releases/download
  export QC01W_BOOT_FIRMWARE_URL=$QC01W_BOOT_FIRMWARE_BASE_URL/$QC01W_UBUNTU_VERSION/Release.tar.gz
  export QC01W_BOOT_FIRMWARE_SHA_URL=$QC01W_BOOT_FIRMWARE_BASE_URL/$QC01W_UBUNTU_VERSION/SHA256SUM
  export QC01W_BOOT_FIRMWARE_SHA=$(basename "$QC01W_BOOT_FIRMWARE_SHA_URL")

  export DOWNLOAD_ISO=0
  export CHECK_SHA=0

  export workfolder=.repack
  mkdir -p $workfolder

  export nhlos_bins_folder=
  export rootfs_folder=
  export dtb_folder=
  export script_folder=

  export rootfs_folder=$PWD/../../rootfs
  export deb_folder=$PWD/../../rootfs/var/qc01w/deb
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
      if [[ "$CHECK_SHA" == "1" ]] && ! check_sha "$local_file_name" "$2"; then
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
  echo "download_boot_firmware"

  mkdir -p boot_firmware >/dev/null 2>&1
  pushd boot_firmware >/dev/null 2>&1

  curl -LO $QC01W_BOOT_FIRMWARE_SHA_URL

  CHECK_SHA=1
  download_file $QC01W_BOOT_FIRMWARE_URL $QC01W_BOOT_FIRMWARE_SHA

  tar zxvf $(basename "$QC01W_BOOT_FIRMWARE_URL") >/dev/null 2>&1

  nhlos_bins_folder=$PWD/Release/nhlos-bins
  rootfs_folder=$PWD/Release/rootfs
  dtb_folder=$PWD/Release/dtb
  script_folder=$PWD/Release/script

  popd >/dev/null 2>&1
}

download_ubuntu_iso()
{
  echo "download_ubuntu_img"

  if [ "$DOWNLOAD_ISO" == "1"  ]; then
    if [ "$CHECK_SHA" == "1" ]; then
      echo "download_ubuntu_img_SHA"
      curl -O $UBUNTU_SHA_URL
      sed -i '/build_info/d' SHA256SUMS
      sed -i '/rawprogram0_emmc/d' SHA256SUMS
    fi

    download_file $UBUNTU_ISO_URL $UBUNTU_SHA
    download_file $UBUNTU_rawprogram0_URL $UBUNTU_SHA
    download_file $UBUNTU_dtb_URL $UBUNTU_SHA

    # backup dtb cause we need a clean version during repack
    cp $UBUNTU_dtb $UBUNTU_dtb.bak

    echo "extract ubuntu image ....."
    unxz -k $UBUNTU_ISO >/dev/null 2>&1

    echo "Backup ISO Image for once..will take a while"
    # backup for refreshing in mount_ubuntu_iso()
    cp $UBUNTU_img $UBUNTU_img.bak
  fi
}

mount_ubuntu_iso()
{
  echo "mount_ubuntu_img...will take a while."

  # refreshing the image
  rm $UBUNTU_img
  cp $UBUNTU_img.bak $UBUNTU_img

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
  echo "umount_ubuntu_img"

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

patch_file()
{
  echo "patch_file"

  pushd mnt/etc/default/grub.d >/dev/null 2>&1
  if [ ! -f "99-dragonwing-defaults.cfg.org" ]; then
    sudo -S sed -i 's|console=ttyMSM0,115200n8 |console=ttyMSM0,115200n8 dwc.pci=blacklist_bdf=0x208 firmware_class.path=\"/etc\" |' 99-dragonwing-defaults.cfg
    sudo -S cp 99-dragonwing-defaults.cfg 99-dragonwing-defaults.cfg.org
  fi
  popd >/dev/null 2>&1

  pushd mnt/boot/grub >/dev/null 2>&1
  if [ ! -f "grub.cfg.org" ]; then
    sudo -S sed -i 's|console=ttyMSM0,115200n8 |console=ttyMSM0,115200n8 dwc.pci=blacklist_bdf=0x208 firmware_class.path=\"/etc\" |' grub.cfg
    sudo -S cp grub.cfg grub.cfg.org
  fi
  popd >/dev/null 2>&1

  #force to use xorg
  sudo -S sed -i 's/#WaylandEnable=false/WaylandEnable=false/' mnt/etc/gdm3/custom.conf
}

cp_rootfs_into_iso()
{
  echo "cp_rootfs_into_iso"

  pushd mnt >/dev/null 2>&1
# no need to clean deb since we have a clean iso image during mount process
  #sudo rm var/qc01w/deb/linux-*.deb
  sudo -S cp -r $rootfs_folder/* .

  popd >/dev/null 2>&1
}

gen_release()
{
  echo "gen_release"

  mkdir -p Release >/dev/null 2>&1
  pushd Release >/dev/null 2>&1

  cp -r $nhlos_bins_folder/* .
  cp -r $dtb_folder/* .
  cp -r $script_folder/* .
  cp ../$workfolder/$UBUNTU_img .
  cp ../$workfolder/$UBUNTU_rawprogram0 .
  popd >/dev/null 2>&1
}

repack_main()
{
  sudo echo "start repack"

  init_env
  pushd $workfolder >/dev/null 2>&1

  download_ubuntu_iso
  download_boot_firmware

  mount_ubuntu_iso

  patch_file
  #enable_service
  cp_rootfs_into_iso

  #read -n 1 -s -r -p "Press any key to continue..."

  umount_ubuntu_iso

  popd >/dev/null 2>&1

  gen_release
}

[[ -z "$1" ]] && repack_main
