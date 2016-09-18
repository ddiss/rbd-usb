#!/bin/bash -x

function _usage {
	echo "$0 <mmc root path> [<ceph dir>]"
	echo "	mmc root path:	mount point of the USB device root filesystem"
	echo "	ceph dir:	top-level Ceph source directory (optional)"
	exit 1
}

function _fatal {
	echo "FATAL: $*"
	exit 1
}

[ -z "$1" ] && _usage

rbd_usb_src=`dirname $0`
mmc_root=$1
ceph_dir=$2

[ -d "$mmc_root" ] || _fatal "mmc root dir does not exist"
[ -d "${mmc_root}/bin" ] || _fatal "mmc bin dir does not exist"
[ -d "${mmc_root}/etc" ] || _fatal "mmc etc dir does not exist"
mkdir -p ${mmc_root}/etc/rbd-usb/ || _fatal "failed to create dir"

cp rbd-usb.conf ${mmc_root}/etc/rbd-usb/ || _fatal "failed to install script"
cp rbd-usb.env ${mmc_root}/usr/lib/ || _fatal "failed to install script"
cp conf-fs.sh ${mmc_root}/bin/ || _fatal "failed to install script"
cp rbd-usb.sh ${mmc_root}/bin/ || _fatal "failed to install script"
cp rbd-usb.service ${mmc_root}/lib/systemd/system/ \
	|| _fatal "failed to install script"
# ensure that the configuration LU is exposed and processed
touch ${mmc_root}/usr/lib/rbd-usb-run-conf.flag || _fatal "touch failed"
if [ -z "$ceph_dir" ]; then
	echo "<ceph dir> not set - ceph-rbdnamer and udev rule not installed"
	exit 0
fi

cp ${ceph_dir}/udev/50-rbd.rules ${mmc_root}/lib/udev/rules.d \
	|| _fatal "failed to install ceph udev file"
cp ${ceph_dir}/src/ceph-rbdnamer ${mmc_root}/usr/bin/ceph-rbdnamer \
	|| _fatal "failed to install ceph udev file"
