#!/bin/bash

CONFIG_FILES="configure.sh iptables.rules nftables.conf"

# print an error and exit with failure
#  $1: error message
function error() {
	echo "$0: error: $1" >&2
	exit 1
}

# ensure the programs and configuration files needed to execute are available
# add config file command line parameter $1 to list
function check_pre_reqs() {
	CONFIG_FILES="$CONFIG_FILES $1"

	local FILES=(${CONFIG_FILES})
	for f in ${FILES[@]}
	do
		[[ -f $f  ]] || error "Missing configuration file: $f"
	done
	CONF_FILE="$1"

	local PROGS="bootctl parted mkfs.vfat mkfs.ext4 mount umount lsblk pacman pacstrap genfstab arch-chroot"
	which ${PROGS} > /dev/null 2>&1 || error "Searching PATH fails to find executables among: ${PROGS}"
}

# load configuration options
function load_config() {
	source ${CONF_FILE}

	[[ "$FIRMWARE_TYPE" == "BIOS" || "$FIRMWARE_TYPE" == "UEFI" ]] || error "Valid firmware types are 'BIOS' or 'UEFI'."
	[[ -b ${BLOCK_DEVICE} ]] || error "${BLOCK_DEVICE} is not a block device"
	[[ -n ${HOST} && -n ${USER} && -n ${T_ZONE} ]] || error "One or more configuration options empty or unset" 
	#ADD/REMOVE package lists and KERNEL_PARAMS can be empty
	
	ADD_PKGS=(${ADD})
	RMV_PKGS=($REMOVE)
}

# prepare partitions for installation
# create partitions, format file systems and mount
function prep_partitions() {
	[[ "$FIRMWARE_TYPE" == "BIOS" ]] && build_mbr || build_gpt
	
	ROOT_PARTUUID=$(lsblk --noheadings --output PARTUUID ${ROOT_PART})
}

# build a GPT partition scheme suitable for UEFI boot
# 1 vfat formatted EFI System Partition (ESP)
# 1 ext4 formatted root partition
function build_gpt() {
	ESP="${BLOCK_DEVICE}1"
	ROOT_PART="${BLOCK_DEVICE}2"
	
	parted --script "${BLOCK_DEVICE}" mklabel gpt
	parted --script --align optimal "${BLOCK_DEVICE}" mkpart primary fat32 1MiB 551MiB set 1 esp on name 1 BOOT
	parted --script --align optimal "${BLOCK_DEVICE}" mkpart primary ext4 551MiB 100% name 2 SYSTEM
	mkfs.vfat -F32 -n BOOT "${ESP}"
	mkfs.ext4 -L SYSTEM "${ROOT_PART}"
	mount --verbose "${ROOT_PART}" /mnt
	mkdir /mnt/boot
	mount --verbose "${ESP}" /mnt/boot
}

# build a MBR partition scheme suitable for BIOS boot
# 1 ext4 formatted root partition
function build_mbr() {
	ROOT_PART="${BLOCK_DEVICE}1"

	parted --script "${BLOCK_DEVICE}" mklabel msdos
	parted --script --align optimal "${BLOCK_DEVICE}" mkpart primary ext4 0% 100%
	mkfs.ext4 -L SYSTEM "${ROOT_PART}"
	mount --verbose "${ROOT_PART}" /mnt
}

# build the package list
function build_pkg_list() {
	PKG_LIST_FILE=$(mktemp)
	pacman --sync --refresh --refresh
	$(pacman --sync --quiet --groups base > ${PKG_LIST_FILE})
	for pkg in "${RMV_PKGS[@]}"
	do
		sed --in-place "/^${pkg}/ d" ${PKG_LIST_FILE}
	done

	PKG_LIST="$(cat ${PKG_LIST_FILE}) ${ADD_PKGS[@]}"
}

# copy required files into chroot
function pre_chroot() {
	local FILES=(${CONFIG_FILES})
	for f in ${FILES[@]}
	do
		cp ./$f /mnt
	done
}

# install packages
function install() {
	echo 'Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch' > /etc/pacman.d/mirrorlist
	pacstrap /mnt ${PKG_LIST}
	genfstab -U /mnt >> /mnt/etc/fstab
}

# cleanup, unmount & poweroff or reboot
function post_chroot() {
	local FILES=(${CONFIG_FILES})
	for f in ${FILES[@]}
	do
		rm -f /mnt/$f
	done

	umount /mnt/boot /mnt
	echo "poweroff, set newly configured disk as first boot option, boot"
}

# Entry point
function main() {
	check_pre_reqs "$@"
	load_config
	prep_partitions
	build_pkg_list
	install
	pre_chroot
#	arch-chroot /mnt ./configure.sh $ROOT_PARTUUID $HOST $USER $T_ZONE $KERNEL_PARAMS $FIRMWARE_TYPE $BLOCK_DEVICE
	arch-chroot /mnt ./configure.sh $ROOT_PARTUUID $CONF_FILE
	post_chroot
}

main "$@"
