#!/bin/bash -x

# import common functions and rbd-usb.conf config
. /usr/lib/rbd-usb.env

function _tcm_iblock_create() {
	local bstore=$1
	local iblock_dev=$2
	local unit_serial=$3

	modprobe target_core_mod

	cd /sys/kernel/config/target/core/ || _fatal "failed TCM configfs entry"

	mkdir -p iblock_0/${bstore} || _fatal "failed to create iblock node"
	echo "udev_path=${iblock_dev}" > iblock_0/${bstore}/control \
		|| _fatal "failed to provision iblock device"
	echo "${unit_serial}" > iblock_0/${bstore}/wwn/vpd_unit_serial \
		|| _fatal "failed to set serial number"

	echo "1" > iblock_0/${bstore}/enable || _fatal "failed to enable iblock"
	# needs to be done after enable, as target_configure_device() resets it
	#echo "openSUSE" > iblock_0/${bstore}/wwn/vendor_id \
	#	|| _fatal "failed to set vendorid"
}

function _tcm_iblock_remove() {
	local bstore=$1

	cd /sys/kernel/config/target/core/ || _fatal "failed TCM configfs entry"

	# `echo "0" > iblock_0/${bstore}/enable` not supported (or needed)

	rmdir iblock_0/${bstore} || _fatal "failed to delete iblock node"
	rmdir iblock_0 || _fatal "failed to delete iblock node"
}

function _tcm_usb_expose() {
	local bstore=$1
	local vendor_id=$2
	local product_id=$3

	modprobe usb_f_tcm

	cd /sys/kernel/config/usb_gadget \
		|| _fatal "failed USB gadget configfs entry"
	mkdir tcm || _fatal "failed USB gadget configfs I/O"
	cd tcm
	mkdir functions/tcm.0 || _fatal "failed USB gadget configfs I/O"

	cd /sys/kernel/config/target/ || _fatal "failed TCM configfs entry"
	mkdir usb_gadget || _fatal "failed TCM gadget configfs I/O"
	cd usb_gadget
	mkdir naa.0123456789abcdef || _fatal "failed TCM gadget configfs I/O"
	cd naa.0123456789abcdef
	mkdir tpgt_1 || _fatal "failed TCM gadget configfs I/O"
	cd tpgt_1
	echo naa.01234567890abcdef > nexus \
		|| _fatal "failed TCM gadget configfs I/O"
	echo 1 > enable || _fatal "failed TCM gadget configfs I/O"

	mkdir lun/lun_0 || _fatal "failed to provision TCM gadget LUN"

	ln -s /sys/kernel/config/target/core/iblock_0/${bstore} \
		lun/lun_0/${bstore} || _fatal "TCM gadget LUN symlink failed"

	cd /sys/kernel/config/usb_gadget/tcm \
		|| _fatal "failed USB gadget configfs entry"
	mkdir configs/c.1 || _fatal "failed USB gadget configfs I/O"
	ln -s functions/tcm.0 configs/c.1
	echo "$vendor_id" > idVendor
	echo "$product_id" > idProduct

	# FIXME: check for /sys/class/udc entry
	ls /sys/class/udc > UDC
}

function _tcm_usb_unexpose() {
	local bstore=$1

	cd /sys/kernel/config/usb_gadget/tcm \
		|| _fatal "failed USB gadget configfs entry"
	rm configs/c.1/tcm.0 || _fatal "failed USB gadget configfs entry"
	rmdir configs/c.1 || _fatal "failed USB gadget configfs entry"

	# FIXME naa. as param
	cd /sys/kernel/config/target/usb_gadget/naa.0123456789abcdef/tpgt_1 \
		|| _fatal "failed USB gadget configfs entry"

	echo 0 > enable
	rm lun/lun_0/${bstore} || _fatal "TCM gadget LUN symlink rm failed"
	rmdir lun/lun_0/ || _fatal "failed TCM gadget configfs I/O"

	cd /sys/kernel/config/target || _fatal "failed configfs I/O"
	rmdir usb_gadget/naa.0123456789abcdef/tpgt_1 \
		|| _fatal "failed TCM gadget configfs I/O"

	rmdir usb_gadget/naa.0123456789abcdef \
		|| _fatal "failed TCM gadget configfs I/O"

	rmdir usb_gadget \
		|| _fatal "failed TCM gadget configfs I/O"

	cd /sys/kernel/config/usb_gadget \
		|| _fatal "failed USB gadget configfs entry"

	rmdir tcm/functions/tcm.0 || _fatal "failed USB gadget configfs I/O"

	rmdir tcm || _fatal "failed USB gadget configfs I/O"
}

function _mon_ping() {
	# could be a hostname or IP:PORT
	local mon_addr=$1
	local mon_host=${mon_addr%:*}
	local sec_off=0
	local sec_tout=20

	until ping -c 1 $mon_host || [ $sec_off -eq $sec_tout ]; do
		sleep 1
		$(( sec_off++ ))
	done

	[ $sec_off -eq $sec_tout ] && _fatal "failed to contact mon: $mon_host"

	true
}

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

_led_set_blue_only

modprobe rbd

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

if [ -n "$script_start" ]; then
	# TODO drop this wait in favour of a systemd target
	_mon_ping "$MON_ADDRESS" || _fatal "failed to ping mon"

	echo -n "$MON_ADDRESS name=${CEPH_USER},secret=$key \
		 $CEPH_RBD_POOL $CEPH_RBD_IMG -" > /sys/bus/rbd/add

	udevadm settle || _fatal "udev settle failed"

	# assume rbdnamer udev rule sets up the /dev/rbd/$pool/$img symlink
	ceph_rbd_dev=/dev/rbd/${CEPH_RBD_POOL}/${CEPH_RBD_IMG}
	[ -b $ceph_rbd_dev ] || _fatal "$ceph_rbd_dev block device did not appear"

	# FIXME use valid serial number
#	_tcm_iblock_create "${CEPH_RBD_POOL}-${CEPH_RBD_IMG}" \
#			   "$ceph_rbd_dev" "fedcba9876543210"

	#FIXME tcm fails with non-super-speed USB driver:
	# Can't claim all required eps
#	_tcm_usb_expose "${CEPH_RBD_POOL}-${CEPH_RBD_IMG}" \
	_usb_expose "$ceph_rbd_dev" \
		"openSUSE" "Ceph USB" "9876543210fedcba" \
		"0"	# removable media

	_led_set_white_only
else
	[ -z "$script_stop" ] && _fatal "assert failed"

	# _tcm_usb_unexpose "${CEPH_RBD_POOL}-${CEPH_RBD_IMG}"
	_usb_unexpose

#	_tcm_iblock_remove "${CEPH_RBD_POOL}-${CEPH_RBD_IMG}"

	# assume rbdnamer udev rule sets up the /dev/rbd/$pool/$img symlink
	ceph_rbd_dev=/dev/rbd/${CEPH_RBD_POOL}/${CEPH_RBD_IMG}
	[ -b $ceph_rbd_dev ] || _fatal "$ceph_rbd_dev block device did not appear"

	ceph_dev=`readlink -e "$ceph_rbd_dev"`

	_led_set_off
fi

exit 0
