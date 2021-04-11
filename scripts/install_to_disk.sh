# Replace disk.img with another one that can be booted from.
#
# TODO: Figure out how to do this without root and a bunch of utilities. It's
# possible to write the disk image myself if I'm already writing GPT and Ext2
# code for the OS itself. If I can do this I'm not far from having the OS being
# able to install itself. The only major roadblock would be getting GRUB into
# the image. grub-install needs the disk to be a block device that is mounted.

set -e

echo Check for Existing Loop Device ===========================================
if [ ! -z "$(losetup -j disk.img)" ]
then
    for dev in $(losetup -j disk.img | cut -d ':' -f 1)
    do
        echo "Disk image is already a device at $dev, removing..."
        for part_dev in $(mount | grep -s "$dev" | cut -d ' ' -f 1)
        do
            echo "$dev is mounted as $part_dev, unmounting..."
            sudo umount $part_dev
        done
        sudo losetup --detach $dev
    done
fi

echo Create Blank Image =======================================================
rm -f disk.img
dd if=/dev/zero of=disk.img iflag=fullblock bs=1M count=20
sync

echo Create Loop Device =======================================================
sudo losetup --partscan --find --offset 0 disk.img
dev=$(losetup -j disk.img | cut -d ':' -f 1)
read -p "$dev is the device, type Y if this is correct. " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "OK"
else
    echo "Not Y, aborting..."
    exit 1
fi

echo Create Partitions ========================================================
sudo sfdisk $dev < misc/disk.sfdisk

echo Format Ext2 Partition ====================================================
root_dev="${dev}p2"
if [ ! -b $root_dev ]
then
    echo "$root_dev is an invalid block device"
    exit 1
fi
sudo mke2fs -L '' -N 0 -O none -d tmp/root -r 1 -t ext2 $root_dev

echo Mount Ext2 Partition =====================================================
mkdir -p tmp/mount_point
sudo mount $root_dev tmp/mount_point

echo Copy Extra Files =========================================================
sudo cp misc/grub_hd.cfg tmp/mount_point/boot/grub/grub.cfg

echo Install GRUB =============================================================
sudo grub-install --target=i386-pc \
    --root-directory=tmp/mount_point --boot-directory=tmp/mount_point/boot $dev

echo Unmount Ext2 Partition ===================================================
sync
sudo umount tmp/mount_point

echo Remove Loop Device =======================================================
sudo losetup -d $dev
