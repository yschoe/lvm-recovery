# Recovery Session Log

Date: 2026-04-23  
Host context: `yschoe@hp`  
Working area: `~/backup/username-hdd`

## Objective

Inspect `/dev/sdd`, determine mountability, and recover data safely using an image-based workflow.

## Initial Device Inspection

Commands run:

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT,MODEL /dev/sdd
blkid /dev/sdd /dev/sdd1 /dev/sdd2
```

Findings:

- `/dev/sdd1` = `ext3` (200M), mounted at:
  - `/media/yschoe/92781637-2c0b-499d-8ca1-f37d73da6694`
- `/dev/sdd2` = `LVM2_member` (31.3G visible)

## LVM Discovery on Physical Disk

User ran:

```bash
sudo pvscan
sudo vgscan
sudo vgchange -ay
sudo lvs -o +devices
```

Key output:

- VG detected: `vg_amygdala`
- LVs present:
  - `lv_root` = `73.33g`
  - `lv_swap` = `1.00g`
- Critical warning:
  - device `/dev/sdd2` current size is much smaller than PV metadata size
- Activation failed on physical device:
  - `device-mapper: reload ioctl ... failed: Invalid argument`
  - `0 logical volume(s) ... now active`

Interpretation:

- The visible block device (`~31.5GiB`) is smaller than what the LVM metadata expects (`~74.33GiB`), so direct activation on physical `/dev/sdd2` fails.

## Capacity / HPA Check

User ran:

```bash
sudo hdparm -N /dev/sdd
```

Output indicated:

- `max sectors = 66055248/1(156301488?)`
- `HPA setting seems invalid (buggy kernel device driver?)`

Interpretation:

- Current visible sectors are much lower than historical/native-like value.
- Current controller/driver path is unreliable for HPA management.

## Imaging Decision

Decision: proceed with image-based recovery to avoid risky writes to source media and allow repeatable attempts.

## Script Creation and Iteration

Script created:

- `sdd_image_recovery.sh`

Design intent:

- Prompt before every step (`y/N/q`)
- Create clipped image with `ddrescue`
- Build padded working image
- Attach loop device
- Activate and mount LVM read-only
- Copy recovered files

## Important Bug Found and Fixed

Issue observed:

- `sdd-work.img` became `0` bytes during script run.

Root cause:

- `truncate` expression was passed in a way that evaluated to an empty size in the script context.

Fixes applied:

- Added explicit `TARGET_BYTES` variable (`TARGET_SECTORS * 512`)
- Switched to:
  - `sudo cp --reflink=auto ...`
  - `sudo truncate -s "$TARGET_BYTES" ...`

## Manual Rebuild After Wipe

Executed workflow:

```bash
sudo rm -f sdd-work.img
sudo cp --reflink=auto sdd-clipped.img sdd-work.img
sudo truncate -s 80026361856 sdd-work.img
```

## Loop-Only LVM Activation (Breakthrough)

Successful commands:

```bash
sudo lvm pvscan --cache --activate ay --config "devices { global_filter=[ \"a|${LOOP}p2|\", \"r|.*|\" ] }"
sudo lvm vgchange -ay -P vg_amygdala --config "devices { global_filter=[ \"a|${LOOP}p2|\", \"r|.*|\" ] }"
sudo lvm lvs -a -o +devices --config "devices { global_filter=[ \"a|${LOOP}p2|\", \"r|.*|\" ] }"
```

Key output:

- `PV /dev/loop17p2 online, VG vg_amygdala is complete`
- `2 logical volume(s) in volume group "vg_amygdala" now active`
- LVs mapped to `/dev/loop17p2`

Interpretation:

- Image-based loop device path worked and avoided direct physical-device activation issues.

## Script Hardening (Final)

Script updated to make successful path default:

- Uses `losetup -Pf --read-only --show`
- Runs `partx -av` after loop setup
- Replaces fragile `fdisk` dependency in inspection step
- Restricts LVM activation to loop partition (`${LOOPDEV}p2`) via LVM filter
- Preserves step-by-step confirmation prompts

## Additional Task Completed

User asked how to mount ISO files; confirmed working method:

```bash
sudo mkdir -p /mnt/iso
sudo mount -o loop,ro /path/to/file.iso /mnt/iso
sudo umount /mnt/iso
```

## Current Artifacts

- Script:
  - `sdd_image_recovery.sh`
- Recovery workspace:
  - `recovery-sdd/`
- Other observed files:
  - `backup.iso`
  - `iso/`
  - `recovered/`

## Safety Notes

- Avoid write operations on source disk during uncertain geometry state.
- Prefer image-first workflow and read-only mounts for forensic-style recovery.
- Do not run destructive LVM/fs repair commands on source media unless a complete backup strategy is in place.
