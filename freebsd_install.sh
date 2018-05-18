#!/bin/sh
#
FETCH="$(which fetch) --no-verify-peer"
ARCH=$(uname -m)

if [ $# != 3 ]; then
        echo "Usage: freebsd_install.sh disk_name hostname distr"
        exit
else
        export disk_name=$1
		export hostname=$2
		export DIST_NAME=$3
	shift
fi
#
echo "# remove any old partitions on destination drive"
zpool destroy zroot
gpart delete -i 3 ${disk_name}
gpart delete -i 2 ${disk_name}
gpart delete -i 1 ${disk_name}
gpart destroy -F ${disk_name}

echo ""
echo "# Create zfs boot (512k) and a zfs root partition"
gpart create -s gpt ${disk_name}
gpart add -a 4k -s 512k -t freebsd-boot -l boot0 ${disk_name}
echo "# Create swap gpt partition"
gpart add -a 4k -s 2G -t freebsd-swap -l swap0 ${disk_name}
echo "# Create freebsd-zfs gpt partition"
gpart add -a 4k -t freebsd-zfs -l disk0 ${disk_name}
gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 ${disk_name}

echo ""
echo "# Align the Disks for 4K and create the pool"
gnop create -S 4096 /dev/gpt/disk0
zpool create -f -o altroot=/mnt -O canmount=off -m none zroot /dev/gpt/disk0.nop
zpool export zroot
gnop destroy /dev/gpt/disk0.nop
zpool import -f -o altroot=/mnt -o cachefile=/var/tmp/zpool.cache zroot

sleep 5
cd /mnt

echo ""
echo "# Set the bootfs property and set options"
zpool set listsnapshots=on zroot
zpool set autoreplace=on zroot
zfs set checksum=fletcher4 zroot
zfs set compression=lz4 zroot
zfs set atime=off zroot
zfs set copies=2 zroot

zfs create   -o mountpoint=none                                      zroot/ROOT
zfs create   -o mountpoint=/                                         zroot/ROOT/default
zfs create   -o mountpoint=/tmp -o compression=lz4   -o setuid=off   zroot/tmp
chmod 1777 /mnt/tmp
zfs create   -o mountpoint=/usr                                      zroot/usr
zfs create                                                           zroot/usr/local
zfs create   -o mountpoint=/home                     -o setuid=off   zroot/home
zfs create   -o compression=lz4                      -o setuid=off   zroot/usr/ports
zfs create   -o compression=off      -o exec=off     -o setuid=off   zroot/usr/ports/distfiles
zfs create   -o compression=off      -o exec=off     -o setuid=off   zroot/usr/ports/packages
zfs create   -o compression=lz4      -o exec=off     -o setuid=off   zroot/usr/src
zfs create                                                           zroot/usr/obj
zfs create   -o mountpoint=/var                                      zroot/var
zfs create   -o compression=lz4      -o exec=off     -o setuid=off   zroot/var/crash
zfs create                           -o exec=off     -o setuid=off   zroot/var/db
zfs create   -o compression=lz4      -o exec=on      -o setuid=off   zroot/var/db/pkg
zfs create                           -o exec=off     -o setuid=off   zroot/var/empty
zfs create   -o compression=lz4      -o exec=off     -o setuid=off   zroot/var/log
zfs create   -o compression=gzip     -o exec=off     -o setuid=off   zroot/var/mail
zfs create                           -o exec=off     -o setuid=off   zroot/var/run
zfs create   -o compression=lz4      -o exec=on      -o setuid=off   zroot/var/tmp
chmod 1777 /mnt/var/tmp

zpool set bootfs=zroot/ROOT/default zroot

cd /mnt

echo ""
echo "# Install FreeBSD OS from *.txz media"
echo "# This will take a few minutes..."
#mount -rw /
sleep 5

cd /mnt

if [ -f /usr/freebsd-dist/base.txz ]; then
    ls /usr/freebsd-dist/*.txz | grep -v 'doc\|games' | while read f
	do
		echo "Installing ${f}..."
		tar -xf ${f}
	done
else
    for d in "base" "kernel" "src" "ports"
    do
         echo "Downloading ${d}..."
         ${FETCH} https://download.freebsd.org/ftp/releases/${ARCH}/${DIST_NAME}/${d}.txz ./
    done
    cd /mnt
    ls ./*.txz | grep -v 'doc\|games' | while read f
	do
		echo "Installing ${f}..."
		tar -xf ${f}; rm ${f}
	done
fi

echo ""
echo "# Copy zpool.cache to install disk."
mount -t devfs devfs /dev
zfs set readonly=on zroot/var/empty

echo ""
echo "# Setup ZFS root mount and boot"
echo 'zfs_enable="YES"' >> /mnt/etc/rc.conf
echo 'zfs_load="YES"' >> /mnt/boot/loader.conf

echo 'vm.kmem_size="1024M"' >> /mnt/boot/loader.conf
echo 'vm.kmem_size_max="1024M"' >> /mnt/boot/loader.conf
echo 'vfs.zfs.arc="512M"' >> /mnt/boot/loader.conf
echo 'vfs.zfs.arc_max="512M"' >> /mnt/boot/loader.conf
echo 'vfs.zfs.vdev.cache.size="10M"' >> /mnt/boot/loader.conf
echo 'vfs.zfs.prefetch_disable=1' >> /mnt/boot/loader.conf
echo 'beastie_disable="YES"' >> /mnt/boot/loader.conf
echo 'autoboot_delay="-1"' >> /mnt/boot/loader.conf

echo ""
echo "# enable networking, pf and ssh and stop syslog from listening."
echo "hostname=${hostname}" >> /mnt/etc/rc.conf
#
for i in `ifconfig -l` ; do
    [ "$i" != "lo0" ] && echo "ifconfig_$i=\"dhcp\"" >> /mnt/etc/rc.conf
done
#
echo '#pf_enable="YES"' >> /mnt/etc/rc.conf
echo '#pflog_enable="YES"' >> /mnt/etc/rc.conf
echo 'sshd_enable="YES"' >> /mnt/etc/rc.conf
echo 'syslogd_flags="-ss"' >> /mnt/etc/rc.conf
echo 'fsck_y_enable="YES"' >> /mnt/etc/rc.conf
echo 'dumpdev="NO"' >> /mnt/etc/rc.conf

echo ""
echo "# /etc/rc.conf disable sendmail"
echo 'dumpdev="NO"' >> /mnt/etc/rc.conf
echo 'sendmail_enable="NO"' >> /mnt/etc/rc.conf
echo 'sendmail_submit_enable="NO"' >> /mnt/etc/rc.conf
echo 'sendmail_outbound_enable="NO"' >> /mnt/etc/rc.conf
echo 'sendmail_msp_queue_enable="NO"' >> /mnt/etc/rc.conf

swpath=$(glabel status | grep "${disk_name}p2" | grep -v swap | awk '{print $1}')
echo ""
echo "# set the /etc/fstab..."
cat << EOF > /mnt/etc/fstab
# Device                                        Mountpoint   FStype   Options   Dump   Pass#
proc                                            /proc        procfs   rw        0       0
/dev/${swpath} none         swap     sw        0       0
EOF

echo '#!/bin/sh' > /mnt/root/.profile
echo '. /etc/profile' >> /mnt/root/.profile
rm -f /mnt/.profile; ln -sn /etc/profile /mnt/.profile

cd /mnt/etc
for f in "DIR_COLORS" "inputrc" "profile" "bashrc" "make.conf"
do
	${FETCH} https://raw.githubusercontent.com/c2nc/freebsd_install/master/${f}
done

echo ""
echo "# preinstalling software"

cp /etc/resolv.conf /mnt/etc/
mount -t devfs devfs /mnt/dev
mkdir -p /mnt/root/bin
cat << EOF > /mnt/root/bin/preinstall.sh
#!/bin/sh
echo ""
echo "*** installing ports tree..."; sleep 2
portsnap fetch extract
echo ""
echo "*** nupdating packages..."; sleep 2
pkg update
echo ""
echo "*** installing some staff..."; sleep 2
pkg install -y portmaster
portmaster -ygG editors/nano shells/bash misc/mc security/sudo
echo ""
echo "*** setuping root password..."; sleep 1
passwd
echo ""
echo "*** add user..."; sleep 1
adduser
echo ""
echo "# exiting chroot..."; sleep 1
EOF

chmod a+x /mnt/root/bin/preinstall.sh
chroot /mnt /bin/sh -c "/root/bin/preinstall.sh"
umount /mnt/dev
rm -f /mnt/root/bin/preinstall.sh

echo ""
echo "# save zpool cache..."
cp /var/tmp/zpool.cache /mnt/boot/zfs/zpool.cache
zpool set cachefile=/boot/zfs/zpool.cache zroot

exit

#### EOF ####
