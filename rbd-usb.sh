#!/bin/bash

# import common functions and rbd-usb.conf config
. /usr/lib/rbd-usb.env

# parse start/stop parameter
script_start=""
script_stop=""
# network interface name is an optional parameter
net_dev=""
while [[ $# -gt 0 ]]; do
        param="$1"

        case $param in
        --net-dev)
                net_dev="$2"
                shift
                ;;
        --start)
		[ -z "$script_stop" ] || _fatal "invalid param: $param"
                script_start="1"
                ;;
        --stop)
		[ -z "$script_start" ] || _fatal "invalid param: $param"
                script_stop="1"
                ;;
        *)
                _fatal "unknown parameter $param"
                ;;
        esac
        shift
done

if [ -z "$script_start" ] && [ -z "$script_stop" ]; then
	_fatal "invalid parameters: either --stop or --start must be provided"
fi

# ignore events for loopback
[ "$net_dev" == "lo" ] && exit 0

# turn off all LEDs except for blue
if [ -f /sys/class/leds/cubietruck:blue:usr/trigger ]; then
	echo none > /sys/class/leds/cubietruck:green:usr/trigger
	echo none > /sys/class/leds/cubietruck:white:usr/trigger
	echo none > /sys/class/leds/cubietruck:orange:usr/trigger
	echo default-on > /sys/class/leds/cubietruck:blue:usr/trigger
fi

cat /proc/mounts | grep configfs &> /dev/null
if [ $? -ne 0 ]; then
	mount -t configfs configfs /sys/kernel/config \
		|| _fatal "failed to mount configfs"
fi

_ini_parse "/etc/ceph/keyring" "client.${CEPH_USER}"
_keyring_parse ${CEPH_USER}
if [ -z "$CEPH_MON_NAME" ]; then
	# pass global section and use mon_host
	_ini_parse "/etc/ceph/ceph.conf" "global"
	MON_ADDRESS="$mon_host"
else
	_ini_parse "/etc/ceph/ceph.conf" "mon.${CEPH_MON_NAME}"
	MON_ADDRESS="$mon_addr"
fi

echo -n "$MON_ADDRESS name=${CEPH_USER},secret=$key \
	 $CEPH_RBD_POOL $CEPH_RBD_IMG -" > /sys/bus/rbd/add

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
