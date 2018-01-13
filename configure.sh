#!/bin/bash

# print an error and exit with failure
#  $1: error message
function error() {
	echo "$0: error: $1" >&2
	exit 1
}

#check for empty input
function check_input() {
	ROOT_PARTUUID="$1"
	HOST="$2"
	USER="$3"
	T_ZONE="$4"
	
	[[ -n ${ROOT_PARTUUID} && -n ${HOST} && -n ${USER} && -n ${T_ZONE} ]] || error "One or more configuration options empty or unset"

	echo ROOT_PARTUUID="$ROOT_PARTUUID", HOST="$HOST", USER="$USER", T_ZONE="$T_ZONE"
}

#timezone configuration
function cfg_time() {
	ln --verbose --symbolic --force /usr/share/zoneinfo/${T_ZONE} /etc/localtime
	hwclock --systohc
}

#locale configuration
function cfg_locale() {
	sed --in-place 's/^#en_CA.UTF-8/en_CA.UTF-8/' /etc/locale.gen
	sed --in-place 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
	locale-gen
	echo "LANG=en_US.UTF-8" >> /etc/locale.conf
}

#networking
function cfg_networking() {
	echo "$HOST" >> /etc/hostname #hostnamectl doesn't work within arch-chroot
	systemctl enable dhcpcd.service
}

#ntp
function cfg_ntp() {
	sed --in-place 's/arch.pool.ntp.org/ca.pool.ntp.org iburst/' /etc/ntp.conf
	systemctl enable ntpd.service
}

#iptables
function cfg_iptables() {
#echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/30-ipforward.conf
	cp ./iptables.rules /etc/iptables
	systemctl enable iptables.service
}

#root pw, $USER account & sudo configuration
function cfg_accounts() {
	echo "root:password" | chpasswd
	useradd --create-home --groups wheel --shell /bin/zsh "$USER"
	echo "${USER}:password" | chpasswd
	#cat ./zshrc >> "/home/${USER}/.zshrc"
	sed --in-place 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
}

#bootloader installation, pacman hook & menu entries
function cfg_bootloader() {
	local HOOK="/etc/pacman.d/hooks/systemd-boot.hook"
	local LOADER="/boot/loader/loader.conf"
	local ARCH_ENTRY="/boot/loader/entries/arch.conf"
	local ARCH_FALLBACK_ENTRY="/boot/loader/entries/arch-fallback.conf"
	bootctl --path=/boot install
	
	mkdir /etc/pacman.d/hooks
cat << EOF > $HOOK
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Updating systemd-boot...
When = PostTransaction
Exec = /usr/bin/bootctl update
EOF

cat << EOF > $LOADER
default		arch
timeout		5
editor		0
EOF

cat << EOF > $ARCH_ENTRY
title		Arch Linux
linux		/vmlinuz-linux
initrd		/intel-ucode.img
initrd		/initramfs-linux.img
options		root=PARTUUID=${ROOT_PARTUUID} rw init=/usr/lib/systemd/systemd fbcon=scrollback:128k ipv6.disable=1
EOF
	
cat << EOF > $ARCH_FALLBACK_ENTRY
title		Arch Linux (fallback initramfs)
linux		/vmlinuz-linux
initrd		/intel-ucode.img
initrd		/initramfs-linux-fallback.img
options		root=PARTUUID=${ROOT_PARTUUID} rw init=/usr/lib/systemd/systemd fbcon=scrollback:128k ipv6.disable=1
EOF
}

#sshd; disable root login, allow access only for $USER
function cfg_sshd() {
	sed --in-place 's/^#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
	echo "AllowUsers $USER" >> /etc/ssh/sshd_config
	systemctl enable sshd.socket
}

# set vim as the default editor & setup a basic zsh config
function cfg_env() {
	local ZSHRC=/home/${USER}/.zshrc
	local ZSHRC_LOCAL=/home/${USER}/.zshrc.local
	echo -e 'EDITOR=vim' > /etc/environment
	touch $ZSHRC $ZSHRC_LOCAL
}

# Entry point
function main() {
	check_input "$@"
	cfg_time
	cfg_locale
	cfg_networking
	cfg_ntp
	cfg_iptables
	cfg_accounts
	cfg_bootloader
	cfg_sshd
	cfg_env
}

main "$@"
