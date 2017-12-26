#!/bin/bash

readonly CONFFILE="auto-install.conf"
readonly CONFIG_FILES="configure.sh iptables.rules"

# print an error and exit with failure
#  $1: error message
function error() {
	echo "$0: error: $1" >&2
	exit 1
}

# ensure the programs and configuration files needed to execute are available
function check_pre_reqs() {
	local PROGS="parted mkfs.vfat mkfs.ext4 mount lsblk pacman pacstrap genfstab arch-chroot"
	#local PROGS="parted mkfs.vfat mkfs.ext4 mount lsblk pacman"
	which ${PROGS} > /dev/null 2>&1 || error "Searching PATH fails to find executables among: ${PROGS}"

	local FILES=(${CONFIG_FILES})
	for f in ${FILES[@]}
	do
		[[ -f $f  ]] || error "Missing configuration file: $f"
	done
}

# load configuration options
# any options not defined in the configuration file are set to default values
# any options overridden in the configuration file to empty or null values cause the script to exit with failure
function load_config() {
	BLOCK_DEVICE="/dev/vda"
	HOST="arch-test"
	USER="jules"
	T_ZONE="Canada/Pacific"

	source ${CONFFILE}

	[[ -b ${BLOCK_DEVICE} ]] || error "${BLOCK_DEVICE} is not a block device"
	[[ -n ${HOST} && -n ${USER} && -n ${T_ZONE} ]] || error "One or more configuration options empty or unset" 
	
	ESP="${BLOCK_DEVICE}1"
	ROOT_PART="${BLOCK_DEVICE}2"
	ADD_PKGS=(${ADD})
	RMV_PKGS=($REMOVE)
}

# prepare partitions for installation
# create partitions, format file systems and mount
function prep_partitions() {
	parted --script "${BLOCK_DEVICE}" mklabel gpt
	parted --script --align optimal "${BLOCK_DEVICE}" mkpart primary fat32 1MiB 551MiB set 1 esp on name 1 BOOT
	parted --script --align optimal "${BLOCK_DEVICE}" mkpart primary ext4 551MiB 100% name 2 SYSTEM
	mkfs.vfat -F32 -n BOOT "${ESP}"
	mkfs.ext4 -L SYSTEM "${ROOT_PART}"
	mount --verbose "${ROOT_PART}" /mnt
	mkdir /mnt/boot
	mount --verbose "${ESP}" /mnt/boot

	ROOT_PARTUUID=$(lsblk --noheadings --output PARTUUID ${ROOT_PART})
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
	echo 'Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch' >> /etc/pacman.d/mirrorlist
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
	check_pre_reqs
	load_config
	prep_partitions
	build_pkg_list
	install
	pre_chroot
	arch-chroot /mnt ./configure.sh $ROOT_PARTUUID $HOST $USER $T_ZONE
	post_chroot
}

main "$@"
