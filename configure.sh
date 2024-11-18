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
	sed --in-place 's/#NTP=/NTP=0.ca.pool.ntp.org 1.ca.pool.ntp.org 2.ca.pool.ntp.org 3.ca.pool.ntp.org/' /etc/systemd/timesyncd.conf
	systemctl enable systemd-timesyncd.service
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

#firewall; nftables and iptables configurations exist; nftables is the default
function cfg_firewall() {
#echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/30-ipforward.conf
	cp ./iptables.rules /etc/iptables
	cp ./nftables.conf /etc
	systemctl enable nftables.service
}

#root pw, $USER account & sudo configuration
function cfg_accounts() {
	echo "root:password" | chpasswd
	useradd --create-home --groups wheel --shell /bin/zsh "$USER"
	echo "${USER}:password" | chpasswd
}

#enable sudo capability for 'wheel' group members; relax pw input requirements for admin user
function cfg_sudoers() {
	sed --in-place 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
	echo "User_Alias ADMINS = ${USER}" >> /etc/sudoers.d/14-admin-timestamp
	echo "Defaults:ADMINS timestamp_timeout=15, timestamp_type=global" >> /etc/sudoers.d/14-admin-timestamp
}

#bootloader installation
function cfg_bootloader() {
	local LOADER="/boot/loader/loader.conf"
	local ARCH_ENTRY="/boot/loader/entries/arch.conf"
	local ARCH_FALLBACK_ENTRY="/boot/loader/entries/arch-fallback.conf"
	bootctl --path=/boot install
	
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

#pacman_hooks for systemd-boot and pacman cache
function cfg_pacman_hooks() {
        local SYSTEMD_BOOT_HOOK="/etc/pacman.d/hooks/systemd-boot.hook"
        local PACCACHE_HOOK="/etc/pacman.d/hooks/paccache.hook"
        mkdir /etc/pacman.d/hooks

cat << EOF > $PACCACHE_HOOK
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Package
Target = *

[Action]
Description = Cleaning pacman cache...
When = PostTransaction
Exec = /usr/bin/paccache --remove
EOF

cat << EOF > $SYSTEMD_BOOT_HOOK
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Updating systemd-boot...
When = PostTransaction
Exec = /usr/bin/bootctl update
EOF
}

#sshd; disable root login, allow access only for $USER
function cfg_sshd() {
	sed --in-place 's/^#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
	echo "AllowUsers $USER" >> /etc/ssh/sshd_config
	systemctl enable sshd.socket
}

# create basic zsh config files; set vim as the default editor; enable pacman colour
function cfg_env() {
	local ZSHRC=/home/${USER}/.zshrc
	local ZSHRC_LOCAL=/home/${USER}/.zshrc.local
	touch $ZSHRC $ZSHRC_LOCAL
	echo -e 'EDITOR=vim' > /etc/environment
	sed --in-place 's/#Color/Color/' /etc/pacman.conf
}

# Entry point
function main() {
	check_input "$@"
	cfg_time
	cfg_locale
	cfg_networking
	cfg_firewall
	cfg_accounts
	cfg_sudoers
	cfg_bootloader
	cfg_pacman_hooks
	cfg_sshd
	cfg_env
}

main "$@"
