#!/bin/bash
set -e

# Create a PXE bootable environment from scratch.
# The rootfs image is downloaded to ram and loop mounted.
# Changes to files on the PXE client shall be redirected to ramdisk (tmpfs)
# using an overlay filesystem (aufs/overlayfs).
#
# Resulting files:
# - Rootfs image: ubuntu_<suite>.squashfs
# - Kernel image: vmlinuz...
# - Initramfs image: initrd...
# - Sample pxelinux config file ....

: ${BUILD_DIR:=/build}
: ${TARGET_DIR:=/target}
: ${UBUNTU_SUITE:=noble}
: ${TARGET_HOSTNAME:=rescue}
: ${ROOTFS_IMAGE:=ubuntu_$UBUNTU_SUITE.squashfs}
# : ${MIRROR:=http://archive.ubuntu.com/ubuntu}
: ${MIRROR:=http://de.archive.ubuntu.com/ubuntu}
: ${FILE_SERVER_URL:=http://192.168.1.1/ubuntu_rescue}

REQUIRED_TOOLS="debootstrap mksquashfs"
COMPONENTS=main,universe
DEBOOTSTRAP_DIR=${BUILD_DIR}/debootstrap

function print_sources_list {
  echo "deb $MIRROR ${UBUNTU_SUITE} main universe"
  echo "deb $MIRROR ${UBUNTU_SUITE}-updates main universe"
}

if [ ! -d "$BUILD_DIR" ]; then
    mkdir -p "$BUILD_DIR"
fi

print_sources_list > /etc/apt/sources.list
apt-get update && apt-get install -y debootstrap squashfs-tools

for tool in $REQUIRED_TOOLS; do
    if ! which $tool >/dev/null; then
        echo "Required tool is missing: $tool. Exiting."
        exit 1
    fi
done

if [ $(id -u) -ne 0 ]; then
    echo "This script needs to be started with root privileges. Exiting."
    exit 2
fi

mkdir -p $TARGET_DIR/tftp
mkdir -p $TARGET_DIR/www
debootstrap --components $COMPONENTS $UBUNTU_SUITE ${DEBOOTSTRAP_DIR} $MIRROR

# Modifications
print_sources_list > ${DEBOOTSTRAP_DIR}/etc/apt/sources.list

# Copy target_files to target
cp -a target_files/* ${DEBOOTSTRAP_DIR}
chmod +x ${DEBOOTSTRAP_DIR}/usr/local/sbin/*

chroot ${DEBOOTSTRAP_DIR} /bin/sh <<EOF
mount -t proc proc /proc
locale-gen de_DE.UTF-8 en_US.utf8
update-locale LANG=de_DE.UTF-8
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
# Override GRUB install dialog
echo "grub-pc grub-pc/install_devices_empty boolean true" | debconf-set-selections
# Install additional packages based on extra_packages file
apt-get install --no-install-recommends -y $(xargs < /extra_packages)
apt-get clean
umount /proc
EOF

# Delete SSH host keys and intergrate hook scripts
rm -f ${DEBOOTSTRAP_DIR}/etc/ssh/ssh_host_*key*
sed -i '/^ExecStart/iExecStartPre=/usr/local/sbin/prepare_ssh_host_keys.sh' \
${DEBOOTSTRAP_DIR}/lib/systemd/system/ssh.service
if [ -f ${DEBOOTSTRAP_DIR}/lib/systemd/system/networking.service ]; then
  sed -i -e '/^ExecStartPre=/iExecStartPre=/usr/local/sbin/prepare_dhcp_client_config.sh' \
  -e '/^ExecStartPre=/iExecStartPre=/usr/local/sbin/prepare_network_interfaces.sh' \
  ${DEBOOTSTRAP_DIR}/lib/systemd/system/networking.service
fi

# Allow adjustments - load a script <hostname>.sh from bootserver
ln -s /lib/systemd/system/run_customizations.service ${DEBOOTSTRAP_DIR}/etc/systemd/system/multi-user.target.wants/

# Place SSH pubkeys for authentication
mkdir -p -m 700 ${DEBOOTSTRAP_DIR}/root/.ssh/
cp /authorized_keys ${DEBOOTSTRAP_DIR}/root/.ssh/authorized_keys
chmod 600 ${DEBOOTSTRAP_DIR}/root/.ssh/authorized_keys

# Enable sshd by default
ln -s /lib/systemd/system/ssh.service ${DEBOOTSTRAP_DIR}/etc/systemd/system/sshd.service
ln -s /lib/systemd/system/ssh.service ${DEBOOTSTRAP_DIR}/etc/systemd/system/multi-user.target.wants/ssh.service

# Create actual rootfs squashfs image
echo "proc    /proc   proc    defaults   0   0" > ${DEBOOTSTRAP_DIR}/etc/fstab
echo "sysfs   /sys    sysfs   defaults   0   0" >> ${DEBOOTSTRAP_DIR}/etc/fstab
echo "$TARGET_HOSTNAME" > ${DEBOOTSTRAP_DIR}/etc/hostname
sed -i 's/root:x:/root::/' ${DEBOOTSTRAP_DIR}/etc/passwd
mv ${DEBOOTSTRAP_DIR}/boot/vmlinuz* $TARGET_DIR/www/
mv ${DEBOOTSTRAP_DIR}/boot/initrd.img* $TARGET_DIR/www/
rm -f ${DEBOOTSTRAP_DIR}/vmlinuz
rm -f ${DEBOOTSTRAP_DIR}/initrd.img
rm -rf ${DEBOOTSTRAP_DIR}/var/lib/apt/lists/*
rm -rf ${DEBOOTSTRAP_DIR}/usr/lib/firmware/*
mksquashfs ${DEBOOTSTRAP_DIR} $TARGET_DIR/www/$ROOTFS_IMAGE -comp xz -noappend

TEMP_DIR=$(mktemp -d)
(cd $TEMP_DIR; apt-get download syslinux-common pxelinux; dpkg-deb -x pxelinux*.deb .; dpkg-deb -x syslinux-common*.deb .)
cp $TEMP_DIR/usr/lib/PXELINUX/lpxelinux.0 $TARGET_DIR/tftp/
cp $TEMP_DIR/usr/lib/syslinux/modules/bios/ldlinux.c32 $TARGET_DIR/www/
rm -rf $TEMP_DIR
cat > $TARGET_DIR/www/lpxelinux.cfg <<EOF
default rescue
label rescue
  kernel vmlinuz
  append initrd=initrd.img ip=dhcp root=$FILE_SERVER_URL/$ROOTFS_IMAGE overlayroot=tmpfs vga=773
  #append initrd=initrd.img ip=dhcp root=$FILE_SERVER_URL/$ROOTFS_IMAGE overlayroot=tmpfs console=ttyS0,115200n8
EOF
chmod +r $TARGET_DIR/www/vmlinuz*
cat > $TARGET_DIR/tftp/dnsmasq.conf.sample <<EOF
# THIS IS A GENERATED DNSMASQ CONFIG FILE TO DEMONSTRATE
# REQUIRED OPTIONS FOR A PXE BOOTSERVER
interface=ens19
enable-tftp
tftp-root=/srv/tftp

dhcp-range=192.168.55.11,192.168.55.100,1h
dhcp-host=AA:BB:CC:DD:EE:FF,192.168.55.234,infinite,set:remoteconfig
dhcp-boot=lpxelinux.0
dhcp-option-force=tag:remoteconfig,209,$FILE_SERVER_URL/lpxelinux.cfg
dhcp-option-force=tag:remoteconfig,210,$FILE_SERVER_URL/
EOF
