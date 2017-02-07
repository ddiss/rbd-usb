# this script generates an initrd image with everything needed to run
# the RBD USB gateway. rbd_usb.sh is added to the Dracut emergency hooks
# path to ensure that it is triggered on boot.

dracut --no-compress  \
       --kver "`uname -r`" \
       --install "ps rmdir modinfo /lib64/libkeyutils.so.1 \
		  cryptsetup dmsetup \
		  /etc/rbd-usb/rbd-usb.conf /usr/lib/rbd-usb.env \
		  /etc/rbd-usb/luks.key /etc/ceph/ceph.conf /etc/ceph/keyring
		  /usr/lib/udev/rules.d/50-rbd.rules \
		  /usr/lib/udev/rules.d/10-dm.rules \
		  /usr/lib/udev/rules.d/13-dm-disk.rules \
		  /usr/lib/udev/rules.d/95-dm-notify.rules" \
       --add-drivers "rbd musb_hdrc sunxi configfs usb_f_mass_storage \
		      dm-crypt" \
       --no-hostonly --no-hostonly-cmdline \
       --modules "bash base network ifcfg" \
       --include "/bin/rbd_usb.sh" "/lib/dracut/hooks/emergency/02_rbd_usb.sh" \
       myinitrd
