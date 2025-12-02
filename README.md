# qnap-minlin
This is an [autorun.sh](autorun.sh) script for my QNAP TS-131P that provides offsite backup behind NAT without depending on QNAP's cloud.

The first part launches a reverse ssh daemon that connects to a central server, exporting ssh on port 9022 and rsync on port 9873.

That alone is sufficient for offsite backup, but I noticed that QNAP's OS is constantly spinning up the disk, which wastes power and causes unnecessary wear and tear.  We must deal with it.

![the-simpsons-hank-scorpio](https://github.com/user-attachments/assets/a2e40bbc-235d-48ef-aee2-82c9cb3c29a9)

The second part, which I'm calling minlin, wakes up after 10 minutes and kills most of the processes on the NAS.  It also provides a standalone config for ifplugd and dhclient, allowing the NAS to remain connected to the network without depending on QNAP's disk-thrashing nonsense.

To use QNAP's default environment, just reboot the NAS, SSH in, and `rm /tmp/minlin.sh` within 10 minutes.

### Recovery Tip: accessing the raw disk

Here's how I accessed a disk formatted by the TS-131P, from Gentoo Linux:

```
USE=lvm   emerge mdadm lvm2
mdadm --assemble --scan
vgchange -ay --nolocking
lsblk
mount -o ro /dev/vg288/lv1 /mnt/backup-ext
```

Cleanup (assumes there are no other LVM or MD volumes):

```
umount /mnt/backup-ext
vgchange -an
mdadm --stop /dev/md*
```
