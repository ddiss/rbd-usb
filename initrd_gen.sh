dracut --no-compress  \
       --kver "`uname -r`" \
       --install "ps rmdir dd vim grep find df modinfo" \
       --add-drivers "rbd musb_hdrc sunxi configfs" \
       --no-hostonly --no-hostonly-cmdline \
       --modules "bash base network ifcfg" \
       --include /bin/rbd_usb_gw.sh /lib/dracut/hooks/emergency/02_rbd_usb_gw.sh \
       myinitrd
