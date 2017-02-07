#!/bin/bash -x

# import common functions and rbd-usb.conf config
. /usr/lib/rbd-usb.env

function _mon_ping() {
	# could be a hostname or IP:PORT
	local mon_addr=$1
	local mon_host=${mon_addr%:*}
	local sec_off=0
	local sec_tout=20

	until ping -c 1 $mon_host || [ $sec_off -eq $sec_tout ]; do
		sleep 1
		(( sec_off++ ))
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

	if [ -f /etc/rbd-usb/luks.key ]; then
		# user provided a LUKS key, so expose dm-crypt mapped device
		_luks_open /etc/rbd-usb/luks.key $ceph_rbd_dev \
				${CEPH_RBD_POOL}-${CEPH_RBD_IMG}-luks \
			|| _fatal "failed to open $ceph_rbd_dev as LUKS device"
		usb_dev="/dev/mapper/${CEPH_RBD_POOL}-${CEPH_RBD_IMG}-luks"
	else
		# no LUKS key - expose regular RBD device via USB
		usb_dev="$ceph_rbd_dev"
	fi

	_usb_expose "$usb_dev" \
		"openSUSE" "Ceph USB" "9876543210fedcba" \
		"0"	# removable media

	_led_set_white_only
else
	[ -z "$script_stop" ] && _fatal "assert failed"

	_usb_unexpose

	# assume rbdnamer udev rule sets up the /dev/rbd/$pool/$img symlink
	ceph_rbd_dev=/dev/rbd/${CEPH_RBD_POOL}/${CEPH_RBD_IMG}
	[ -b $ceph_rbd_dev ] || _fatal "$ceph_rbd_dev block device did not appear"

	ceph_dev=`readlink -e "$ceph_rbd_dev"`

	_led_set_off
fi

exit 0
