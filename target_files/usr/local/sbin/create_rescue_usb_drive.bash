#!/bin/bash

root_url=$(sed 's/ /\n/g' /proc/cmdline | sed -n '/^root=/s/root=//p')
server_location=$(echo $root_url | sed -n 's|\(.*/\).*|\1|p')
filename=$(echo $root_url | sed -n 's|.*/||p')

if [ -n "$1" ]; then
    usb_device="$1"
else
    # search for usb device
    options=()
    status="on"
    for device in /dev/sd?; do
        if udevadm info $device | grep -q ID_USB_DRIVER=usb-storage; then
            # device is usb-storage
            description=$(lshw -class disk -json | python3 -c "import json; l=json.load(open('/dev/stdin')); print([e['vendor'] + ' ' + e['product'] + ' (' + str(int(e['size']/1000**3)) + 'GB)' for e in l if e['logicalname'] == '$device' and 'vendor' in e][0])")
            options+=($device "$description" $status)
            status="off"
        fi
    done

    if [ -z $options ]; then
        echo "Could not find USB storage devices. Exiting..."
        exit 1
    fi

    usb_device=$(dialog --radiolist "Select USB drive" 10 50 1 "${options[@]}" 3>&1 1>&2 2>&3)
fi

if dialog --colors --yesno 'Do you really want to overwrite this device?\n(ALL DATA WILL BE LOST!)\n\n'"\Z1---> \Zb$usb_device\ZB <---\Z0" 8 50; then
    echo "Wiping disk and creating new rescue system..."
    umount /mnt 2>&-
    sgdisk --zap-all ${usb_device}
    sgdisk --new=1:0:0 --typecode=1:ef00 ${usb_device}
    echo "=== Creating file system ==="
    mkfs.vfat -F32 -n GRUB2EFI ${usb_device}1
    mount -t vfat ${usb_device}1 /mnt
    mkdir /mnt/efi
    echo "=== Writing grub bootloader ==="
    grub-install --removable --boot-directory=/mnt/boot --efi-directory=/mnt/ --target=x86_64-efi ${usb_device}
    mkdir /mnt/live
    cd /mnt/live
    echo "=== Copying $filename ==="
    curl --progress-bar -JLO ${server_location}${filename}
    cd /mnt/boot
    echo "=== Copying initial ramdisk ==="
    curl --progress-bar -JLO ${server_location}initrd.img
    echo "=== Copying linux kernel ==="
    curl --progress-bar -JLO ${server_location}vmlinuz
    {
        echo "timeout=3"
        echo "menuentry \"ubuntu-rescue ($(echo $filename | sed -e 's/ubuntu_//' -e 's/.squashfs//'))\" {"
        echo "    insmod part_gpt"
        echo "    set    root=(hd0,gpt1)"
        echo "    echo   'Loading Linux kernel ...' "
        echo "    linux  /boot/vmlinuz ro console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200 ip=dhcp boot=live toram=$filename"
        echo "    echo   'Loading initial ramdisk ...' "
        echo "    initrd /boot/initrd.img"
        echo "    "
        echo "}"
    } > /mnt/boot/grub/grub.cfg
    cd /
    umount /mnt
else
    echo "Aborted by user. Exiting..."
    exit 2
fi
