#!/usr/bin/env bash
#
# Software License Agreement (BSD License)
#
# Copyright (c) 2012, Eucalyptus Systems, Inc.
# All rights reserved.
#
# Redistribution and use of this software in source and binary forms, with or
# without modification, are permitted provided that the following conditions
# are met:
#
#   Redistributions of source code must retain the above
#   copyright notice, this list of conditions and the
#   following disclaimer.
#
#   Redistributions in binary form must reproduce the above
#   copyright notice, this list of conditions and the
#   following disclaimer in the documentation and/or other
#   materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
# Author: Andrew Hamilton

# Directory used to store the disk image along with the kernel and ramdisk
DIR="/root/debian_image/"
# Which version of Debian to be installed
SUITE="squeeze"
# Architecture of the image to be created
ARCH="amd64"
# Name of the image that you are creating
IMG_NAME="debian-$SUITE-"`date +%y%m%d%H%M`"-$ARCH"
# Where to mount the created disk image
MNT_PNT="/mnt/debian"
# Size of the image to create in Megabytes
SIZE_IN_MB=1024
# Which Hypervisor should we setup the image to use
HYPERVISOR="kvm"
# The packages that are helpful with cloud instances + some to make the OS "complete"
BASE_PKGS="openssh-server,openssh-client,less,vim,curl,locales"
# Add any additional packages that you might want installed here (command separated)
EXTRA_PKGS=""
# Kernel that should be installed on the system
KERNEL="linux-image-$ARCH"
INCLUDE_PKGS=$BASE_PKGS","$KERNEL","$EXTRA_PKGS
# Change this mirror if you would like to use a closer mirror
MIRROR="http://ftp.us.debian.org/debian"
# Which block should we be using for the hypervisor?
if [[ $HYPERVISOR = "kvm" ]]; then
    BLK_DEV="vda"
else
    BLK_DEV="xvda"
fi
# Would you like to see the output from debootstrap?
VERBOSE=""

# Check to make sure that we're running as root since we're mounting files, etc
if [[ ! $UID = 0 ]]; then
    echo "Error: You must run this script as the root user."
    exit 3
fi

# Create the root image
if [[ -z $DIR ]]; then
    DIR=`pwd`
elif [[ ! -d $DIR ]]; then
    mkdir -p $DIR
fi

if [[ -z $IMG_NAME ]]; then
    IMG_NAME="debian-$SUITE-"`date +'%y%m%d%H%M'`"-$ARCH"
fi

if [[ -e $DIR/$IMG_NAME ]]; then
    echo "Error: The image already exists! Please change the name."
    exit 1
fi

dd if=/dev/zero of=$DIR/$IMG_NAME.img bs=1M count=$SIZE_IN_MB

# Add a filesystem
LOOPBACK=`losetup --show -f $DIR/$IMG_NAME.img`

if [[ -z $LOOPBACK ]]; then
    echo "Issue creating the loopback device!"
    exit 2
fi

mkfs.ext3 $LOOPBACK

# Mount it at some mount point
if [[ -z $MNT_PNT ]]; then
    MNT_PNT="/mnt/debian/"
fi

if [[ ! -d $MNT_PNT ]]; then
    mkdir -p $MNT_PNT
fi

mount $LOOPBACK $MNT_PNT

# Check to see if debootstrap is on the system and accessible to us
if [[ -z `which debootstrap` ]]; then
    echo "Error: Could not find debootstrap. Exiting"
    exit 4
fi

# RUN debootstrap
if [[ -n $VERBOSE ]]; then
    debootstrap --verbose --arch=$ARCH --include=$INCLUDE_PKGS $SUITE $MNT_PNT $MIRROR
else
    debootstrap --arch=$ARCH --include=$INCLUDE_PKGS $SUITE $MNT_PNT $MIRROR
fi

mount -t proc /proc $MNT_PNT/proc
mount -t sysfs /sys $MNT_PNT/sys

## Default layout pushed into $MNT_PNT/etc/network/interfaces
cat >>$MNT_PNT/etc/network/interfaces <<EOF

auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

## Remove udev rules for persistent net
sed -i -e '/.*PCI.*/d' -e '/^SUBSYSTEM.*/d' $MNT_PNT/etc/udev/rules.d/70-persistent-net.rules

## Setup the locales on the instance
sed -i 's/# \(en_US.*\)/\1/g' $MNT_PNT/etc/locale.gen
echo "LANG=en_US.UTF-8" >> $MNT_PNT/etc/default/locale
chroot $MNT_PNT locale-gen

## Setup the /etc/hostname file
echo "debian" >$MNT_PNT/etc/hostname

## Setup the /etc/fstab file
cat >$MNT_PNT/etc/fstab <<EOF
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/dev/${BLK_DEV}1       /               ext3    defaults        0       1
/dev/${BLK_DEV}2       /mnt            ext3    defaults        0       0
/dev/${BLK_DEV}3       none            swap    sw              0       0

proc            /proc           proc    defaults        0       0
EOF

## Add in the Eucalyptus rc.local additions to the setup.
wget -O /tmp/new_rc.local https://raw.github.com/eucalyptus/Eucalyptus-Scripts/master/rc.local
sed -i '/exit 0/d' $MNT_PNT/etc/rc.local
cat /tmp/new_rc.local >>$MNT_PNT/etc/rc.local

## Setup and install Euca2ools on the image
chroot $MNT_PNT chroot /mnt/debian_image/ apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C1240596
cat >/mnt/debian_image/etc/apt/sources.list.d/euca2ools.list <<EOF
deb http://downloads.eucalyptus.com/software/euca2ools/2.1/ubuntu lucid main
EOF
chroot $MNT_PNT aptitude update
chroot $MNT_PNT aptitude -y install euca2ools

## Reset the mirror back to the default Debian mirrors incase the mirror is only local
cat >$MNT_PNT/etc/apt/sources.list <<EOF
deb http://ftp.us.debian.org/debian $SUITE main contrib non-free
deb-src http://ftp.us.debian.org/debian $SUITE main contrib non-free
EOF

## Copy out the kernel and ramdisk of the image
cp $MNT_PNT/boot/vmlinuz* $DIR
cp $MNT_PNT/boot/initrd* $DIR

## Finish up with some documentation similar to Ubuntu cloud images
cat >$DIR/build-info.txt <<EOF
serial=`date +%Y%m%d`
orig_prefix=$IMG_NAME
suite=$SUITE
EOF

CHK_PKGS="/tmp/check_pkgs.sh"
cat >$MNT_PNT/$CHK_PKGS <<EOF
for pkg in \`apt-cache pkgnames | sort\`; do 
    VERSION=\`aptitude show \$pkg | grep Version | awk '{print \$2}'\`; 
    echo \"\$pkg \$VERSION\"; 
done 
EOF

chroot $MNT_PNT /bin/bash $CHK_PKGS >$DIR/debian-$SUITE-$ARCH.manifest 
rm $MNT_PNT/$CHK_PKGS

## Unmount the loop device and delete it.
if [[ -z `lsof | grep $MNT_PNT` ]]; then
    umount $MNT_PNT/proc
    umount $MNT_PNT/sys
    umount $LOOPBACK
    losetup -d $LOOPBACK
else
    echo "Note: An additional package that you have installed is running as a service. Please stop all"
    echo "services that might be running on the newly created image."
    echo 
    echo "chroot $MNT_PNT"
    echo
    echo "After all services have been stop and 'lsof | grep $MNT_PNT' does not print any lines then run"
    echo "the following commands to unmount your image and delete the loopback device."
    echo
    echo "umount $MNT_PNT/proc"
    echo "umount $MNT_PNT/sys"
    echo "umount $MNT_PNT"
    echo "losetup -d $LOOPBACK"
fi
