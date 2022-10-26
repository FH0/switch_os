#!/bin/bash

set_variable_if_empty() {
    if [ -z "$(eval echo '$'$1)" ]; then
        eval $1=$2
    fi
}

setting() {
    # ubuntu 20.04
    # set_variable_if_empty netboot_url "http://mirrors.163.com/ubuntu/dists/focal-updates/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64"
    # set_variable_if_empty netboot_url "http://archive.ubuntu.com/ubuntu/dists/focal-updates/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64"

    # ubuntu 18.04
    # set_variable_if_empty netboot_url "http://mirrors.163.com/ubuntu/dists/bionic-updates/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64"
    # set_variable_if_empty netboot_url "http://archive.ubuntu.com/ubuntu/dists/bionic-updates/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64"

    # ubuntu 16.04
    # set_variable_if_empty netboot_url "http://mirrors.163.com/ubuntu/dists/xenial-updates/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64"
    # set_variable_if_empty netboot_url "http://archive.ubuntu.com/ubuntu/dists/xenial-updates/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64"

    # debian 11
    set_variable_if_empty netboot_url "http://repo.huaweicloud.com/debian/dists/bullseye/main/installer-amd64/current/images/netboot/debian-installer/amd64/"
    # set_variable_if_empty netboot_url "http://ftp.debian.org/debian/dists/Debian11.0/main/installer-amd64/current/images/netboot/debian-installer/amd64"

    # debian 10
    # set_variable_if_empty netboot_url "http://mirrors.163.com/debian/dists/Debian10.10/main/installer-amd64/current/images/netboot/debian-installer/amd64"
    # set_variable_if_empty netboot_url "http://ftp.debian.org/debian/dists/Debian10.10/main/installer-amd64/current/images/netboot/debian-installer/amd64"

    # debian 9
    # set_variable_if_empty netboot_url "http://mirrors.163.com/debian/dists/Debian9.13/main/installer-amd64/current/images/netboot/debian-installer/amd64"
    # set_variable_if_empty netboot_url "http://ftp.debian.org/debian/dists/Debian9.13/main/installer-amd64/current/images/netboot/debian-installer/amd64"

    set_variable_if_empty url_domain "$(echo $netboot_url | awk -F '/' '{print $3}')"
    set_variable_if_empty target_os "$(echo $netboot_url | awk -F '/' '{print $4}')"
    set_variable_if_empty root_password "$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)"
    set_variable_if_empty timezone "$(cat /etc/timezone || timedatectl status | grep -m1 -Eo '[a-zA-Z]+/[a-zA-Z]+' || echo Asia/Shanghai)"
    set_variable_if_empty language "${LANG:-C.UTF-8}"
    set_variable_if_empty boot_prefix "$(awk '/\/boot/{print "/boot";exit}' /boot/grub*/grub.cfg)"
    set_variable_if_empty post_script ""
}

check_host() {
    # root user
    if [ "$EUID" != "0" ]; then
        echo "please run this script with root user"
        exit 1
    fi

    # dependencies
    for cmd in wget cpio gzip sed grep find; do
        if ! type $cmd >/dev/null 2>&1; then
            echo "$cmd not found, please install it"
            exit 1
        fi
    done

    # menuentry exist in /boot/grub*/grub.cfg
    if ! grep -q "^menuentry" /boot/grub*/grub.cfg; then
        echo "invalid /boot/grub*/grub.cfg, please reinstall to another linux distro"
        exit 1
    fi
}

print_info() {
    # warning
    echo "Warning: the first partition($(ls /dev/[sv]d[a-z] | head -n1)) will be erased"
    echo

    # variable
    echo "Note: the following variables can be set by environment variable"
    for variable in $(grep -E "^[ \t]+set_variable_if_empty " $0 | awk '{print $2}'); do
        eval echo -e "$variable\\\t= \$$variable"
    done
    echo

    # enter yes to continue
    read -n1 -p "enter Y|y to continue or others to cancel: " yn
    echo
    echo
    if ! echo "$yn" | grep -qE "[Yy]"; then
        exit 0
    fi
}

insert_files_into_initrd() {
    cat >preseed.cfg <<EOF
d-i debian-installer/language string en
d-i debian-installer/country string US
d-i debian-installer/locale string $language

d-i console-setup/ask_detect boolean false
d-i keyboard-configuration/xkb-keymap select us
d-i keyboard-configuration/layoutcode string us
d-i keyboard-configuration/variantcode string

d-i mirror/country string manual
d-i mirror/http/hostname string $url_domain
d-i mirror/http/directory string /$target_os
d-i mirror/http/proxy string

d-i passwd/root-login boolean ture
d-i passwd/make-user boolean false
d-i passwd/root-password password $root_password
d-i passwd/root-password-again password $root_password

d-i time/zone string $timezone

d-i partman/early_command string debconf-set partman-auto/disk "\$(list-devices disk | head -n1)"; \
    debconf-set grub-installer/bootdev "\$(list-devices disk | head -n1)";

d-i partman-auto/init_automatically_partition select Guided - use entire disk
d-i partman-auto/method string regular
d-i partman-lvm/device_remove_lvm boolean true
d-i partman/confirm boolean true
d-i partman/choose_partition select Finish partitioning and write changes to disk
d-i partman-auto/choose_recipe select All files in one partition (recommended for new users) # debian

d-i pkgsel/update-policy select none
tasksel tasksel/first multiselect

popularity-contest popularity-contest/participate boolean false # debian

d-i clock-setup/utc boolean true

d-i grub-installer/only_debian boolean true

d-i finish-install/reboot_in_progress note

d-i preseed/late_command string \
    in-target apt install openssh-server -y; \
    in-target sed -i 's/.*PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config; \
    mv /post_script.sh /target/root; \
    in-target bash /root/post_script.sh || true; \
    in-target rm /root/post_script.sh
EOF

    # unpack
    wget --no-check-certificate -O- "$netboot_url/initrd.gz" | gzip -dv >./initrd

    # preseed
    echo "preseed.cfg" | cpio -H newc -o -A -F ./initrd

    # post_script
    if [ -f "$post_script" ]; then
        cp $post_script post_script.sh
    else
        touch post_script.sh
    fi
    echo "post_script.sh" | cpio -H newc -o -A -F ./initrd

    # pack
    gzip -cvf ./initrd >/boot/initrd-netboot.img
}

download_vmlinuz() {
    wget --no-check-certificate -O /boot/vmlinuz-netboot "$netboot_url/linux"
}

modify_grub2() {
    sed -i '0,/^menuentry/s||set default="0"\
menuentry "netboot" {\
    linux   '$boot_prefix'/vmlinuz-netboot auto=true hostname='$target_os' domain= interface=auto\
    initrd  '$boot_prefix'/initrd-netboot.img\
}\
&|' /boot/grub*/grub.cfg
}

setting
check_host
print_info
insert_files_into_initrd
download_vmlinuz
modify_grub2
reboot
