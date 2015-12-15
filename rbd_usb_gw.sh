#!/bin/bash

# XXX Fill in the following...
# e.g. MON_ADDR="10.10.24.24:6789"
MON_ADDR=""
# e.g. AUTH_NAME="admin"
AUTH_NAME=""
# e.g. AUTH_SECRET="qwoifuwqoeihjfloiqqweRWERf/XZCV3429589=="
AUTH_SECRET=""
# e.g. CEPH_POOL="rbd"
CEPH_POOL=""
# e.g. CEPH_IMG="my_rbd_usb_img"
CEPH_IMG=""
# e.g. CEPH_DEV="/dev/rbd0"
CEPH_DEV=""
# XXX "pretty" device path relies on udev namer
#CEPH_DEV="/dev/rbd/$CEPH_POOL/$CEPH_IMG"

_fatal() {
	if [ -f /sys/class/leds/cubietruck:orange:usr/trigger ]; then
		# flag error via orange LED
		echo default-on > /sys/class/leds/cubietruck:orange:usr/trigger
		echo none > /sys/class/leds/cubietruck:blue:usr/trigger
	fi
	echo "FATAL: $*"
	exit 1
}

net_if=$1

# ignore ifup events for loopback
[ "$net_if" != "lo" ] || exit 0

# turn off all LEDs except for blue
if [ -f /sys/class/leds/cubietruck:blue:usr/trigger ]; then
	echo none > /sys/class/leds/cubietruck:green:usr/trigger
	echo none > /sys/class/leds/cubietruck:white:usr/trigger
	echo none > /sys/class/leds/cubietruck:orange:usr/trigger
	echo default-on > /sys/class/leds/cubietruck:blue:usr/trigger
fi

# for i in rbd sunxi configfs libcomposite usb_f_mass_storage; do
for i in rbd sunxi configfs; do
	modprobe $i || _fatal "failed to load $i kernel module"
done


cat /proc/mounts | grep configfs &> /dev/null
if [ $? -ne 0 ]; then
	mount -t configfs configfs /sys/kernel/config \
		|| _fatal "failed to mount configfs"
fi

echo -n "$MON_ADDR name=${AUTH_NAME},secret=${AUTH_SECRET} ${CEPH_POOL} $CEPH_IMG -" > /sys/bus/rbd/add

udevadm settle || _fatal "udev settle failed"

[ -b $CEPH_DEV ] || _fatal "$CEPH_DEV block device did not appear"

cd /sys/kernel/config/usb_gadget/ || _fatal "usb_gadget not present"

mkdir -p ceph || _fatal "failed to create gadget configfs node"
cd ceph || _fatal "failed to enter gadget configfs node"

echo 0x1d6b > idVendor # Linux Foundation
echo 0x0104 > idProduct # Multifunction Composite Gadget
echo 0x0090 > bcdDevice # v0.9.0

mkdir -p strings/0x409 || _fatal "failed to create 0x409 descriptors"
# FIXME should derive serialnumber from board uuid?
echo "fedcba9876543210" > strings/0x409/serialnumber
echo "openSUSE" > strings/0x409/manufacturer
echo "Ceph USB Drive" > strings/0x409/product

N="usb0"
mkdir -p functions/mass_storage.$N || _fatal "failed to init mass storage gadget"
echo 1 > functions/mass_storage.$N/stall
echo 0 > functions/mass_storage.$N/lun.0/cdrom
echo 0 > functions/mass_storage.$N/lun.0/ro
echo 0 > functions/mass_storage.$N/lun.0/nofua

echo "$CEPH_DEV" > functions/mass_storage.$N/lun.0/file \
	|| _fatal "failed to use $CEPH_DEV as LUN backing device"

C=1
mkdir -p configs/c.$C/strings/0x409 \
	|| _fatal "failed to create 0x409 configuration"
echo "Config $C: mass-storage" > configs/c.$C/strings/0x409/configuration
echo 250 > configs/c.$C/MaxPower
ln -s functions/mass_storage.$N configs/c.$C/ \
	|| _fatal "failed to create mass_storage configfs link"

# FIXME: check for /sys/class/udc entry
ls /sys/class/udc > UDC

if [ -f /sys/class/leds/cubietruck:white:usr/trigger ]; then
	# flag success via white LED
	echo default-on > /sys/class/leds/cubietruck:white:usr/trigger
	echo none > /sys/class/leds/cubietruck:blue:usr/trigger
fi
