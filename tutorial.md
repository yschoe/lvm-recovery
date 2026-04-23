# Manual Recovery Tutorial

This is the manual (no-script) path for recovering data from a clipped/truncated LVM disk using image-first, read-only methods.

## 1) Create a recovery workspace

```bash
mkdir -p ~/backup/username-hdd/recovery-sdd
cd ~/backup/username-hdd/recovery-sdd
```

## 2) Image the source disk with ddrescue

```bash
sudo umount /dev/sdd1 || true
sudo ddrescue -f -n /dev/sdd sdd-clipped.img sdd-clipped.log
sudo ddrescue -d -r3 /dev/sdd sdd-clipped.img sdd-clipped.log
```

## 3) Build a padded working image

Use the historical/full sector count (example below from prior metadata).

```bash
sudo cp --reflink=auto sdd-clipped.img sdd-work.img
sudo truncate -s $((156301488*512)) sdd-work.img
```

## 4) Attach loop device and map partitions

```bash
LOOP=$(sudo losetup -Pf --read-only --show sdd-work.img)
echo "$LOOP"
sudo partx -av "$LOOP"
sudo lsblk -f "$LOOP"
ls -l ${LOOP}p*
```

## 5) Activate LVM from loop partition only

```bash
sudo lvm pvscan --cache --activate ay --config "devices { global_filter=[ \"a|${LOOP}p2|\", \"r|.*|\" ] }"
sudo lvm vgchange -ay -P vg_amygdala --config "devices { global_filter=[ \"a|${LOOP}p2|\", \"r|.*|\" ] }"
sudo lvm lvs -a -o +devices --config "devices { global_filter=[ \"a|${LOOP}p2|\", \"r|.*|\" ] }"
```

Expected: LVs should show as active and backed by `${LOOP}p2`.

## 6) Mount root LV read-only

```bash
sudo mkdir -p /mnt/amygdala
sudo mount -o ro,noload /dev/vg_amygdala/lv_root /mnt/amygdala
mount | rg amygdala
```

## 7) Copy recovered data out

```bash
mkdir -p ~/backup/username-hdd/recovered-amygdala
sudo rsync -aHAX --info=progress2 --ignore-errors /mnt/amygdala/ ~/backup/username-hdd/recovered-amygdala/
```

## 8) Cleanup

```bash
sudo umount /mnt/amygdala || true
sudo vgchange -an vg_amygdala || true
sudo losetup -d "$LOOP"
```

## Safety Notes

- Prefer recovery from image files, not the source disk.
- Keep mounts read-only (`ro,noload`).
- Do not run write-repair commands (`pvresize`, `fsck -y`) on source media during initial recovery.
