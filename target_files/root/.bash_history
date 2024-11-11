mount -L clonezilla /home/partimag
ocs-sr -g auto -e1 auto -e2 -c -r -j2 -p choose restoredisk $(cd /home/partimag; ls -td1 20*-*-*-*-img | head -1) sda
ocs-sr --use-partclone --confirm --clone-hidden-data --smp-gzip-compress --image-size 4096 --postaction choose savedisk $(date '+%Y-%m-%d-%H-img') sda
create_rescue_usb_drive.bash
