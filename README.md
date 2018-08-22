# arch-auto-install
Bash script to automate a basic Arch Linux installation.

###### Usage
* curl --remote-name --location https://github.com/chr0mag/arch-auto-install/archive/v0.7.tar.gz
* tar -zxvf v0.7.tar.gz
* cd arch-auto-install-0.7
* cp default.conf my.conf
* edit my.conf according to your needs
* chmod +x install.sh configure.sh
* ./install.sh my.conf

###### Intended Audience
This script is intended for use by Arch users already familiar with the official [Arch Linux installation](https://wiki.archlinux.org/index.php/Installation_guide) process. This is meant to be used as a quick & simple way to spin up a new environment when a fresh base Arch Linux installation is desired. The intention is to automate the minimum set of steps needed to produce a bootable Arch Linux system accessible over SSH. At which point you can turn things over to your favourite configuration automation software (eg. Ansible, etc...). 

Note that Arch provides Vagrant images for both *libvirt* and *Virtualbox*. These may be a better option if you're looking for a quick setup in those environments.

###### Assumptions
This script makes a whole host of assumptions about the system on which it is run.  Below are a few of the more glaring assumptions any script user should be aware of.
* single disk (eg. /dev/vda or /dev/sda, etc.)
* no LVM, LUKS, SecureBoot or other fancyness
* running on a network w/DHCP enabled
* execution from a system booted using the latest [Arch Linux Install Image](https://www.archlinux.org/download/)

###### Resulting System
* Either a BIOS/MBR partition scheme with GRUB2 bootloader or GPT/UEFI with systemd-boot bootloader
* no SWAP partition; (a [swapfile](https://wiki.archlinux.org/index.php/Swap#Swap_file) can easilly be added post-install)
* simple nftables stateful [firewall](https://wiki.archlinux.org/index.php/Nftables#Simple_stateful_firewall) enabled with port 22 open
* $USER account with sudo priviledges
* ZSH as the default shell for the provided $USER; with the [Grml ZSH](https://grml.org/zsh/) configuration enabled
* SSHd enabled with only the provided $USER allowed

###### Sources
* https://shirotech.com/linux/how-to-automate-arch-linux-installation - similar project
* https://wiki.archlinux.org/ - the official Arch Linux wiki
