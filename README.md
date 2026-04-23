# sdd-image-recovery

Interactive, prompt-driven recovery helper for a clipped/truncated LVM disk workflow (`/dev/sdd` case).

This project focuses on safe, repeatable recovery:

- image first (`ddrescue`)
- recovery from loop-mounted image
- read-only mount for extraction
- explicit confirmation before each command

## What This Solves

When a physical disk appears smaller than historical LVM metadata size, direct `vgchange -ay` on the physical PV can fail (for example: `device-mapper reload ioctl ... Invalid argument`).

This script avoids that failure mode by:

1. Imaging the visible disk safely.
2. Building a padded working image to expected PV geometry.
3. Activating LVM from the loop image partition only.
4. Mounting the LV read-only for extraction.

## Repository Contents

- `sdd_image_recovery.sh`: Main interactive recovery script.
- `log.md`: Detailed session and troubleshooting history.

## Requirements

- Linux environment with sudo access.
- Tools:
  - `ddrescue`
  - `lvm2` (`lvm`, `pvscan`, `vgchange`, etc.)
  - `losetup`, `partx`, `lsblk`, `rsync`
- Enough disk space for image files (source-size dependent).

## Quick Start

```bash
chmod +x ./sdd_image_recovery.sh
./sdd_image_recovery.sh
```

The script prompts before each step with:

- `y`: run step
- `n` or Enter: skip step
- `q`: quit script

## Default Flow

1. Create working directory.
2. (Optional) unmount `${DEVICE}1`.
3. Create clipped image with `ddrescue` (fast pass + retries).
4. Copy to working image and pad to expected bytes.
5. Attach working image via read-only loop device.
6. Create partition mappings (`partx`).
7. Activate LVM from loop partition only (`${LOOPDEV}p2` filter).
8. Mount LV read-only (`ro,noload`).
9. Copy recovered data via `rsync`.
10. Cleanup (unmount, deactivate VG, detach loop).

## Common Usage Patterns

### Run from scratch

```bash
./sdd_image_recovery.sh
```

### Reuse existing image

If `sdd-clipped.img` already exists, skip imaging steps by answering `n` for `ddrescue` prompts.

### Override defaults

```bash
DEVICE=/dev/sdd \
WORKDIR=$HOME/backup/jrchung-hdd/recovery-sdd \
TARGET_SECTORS=156301488 \
VG_NAME=vg_amygdala \
LV_NAME=lv_root \
./sdd_image_recovery.sh
```

## Configuration Variables

- `DEVICE` (default: `/dev/sdd`)
- `WORKDIR` (default: `$HOME/backup/jrchung-hdd/recovery-sdd`)
- `CLIPPED_IMG` (default: `sdd-clipped.img`)
- `CLIPPED_LOG` (default: `sdd-clipped.log`)
- `WORK_IMG` (default: `sdd-work.img`)
- `TARGET_SECTORS` (default: `156301488`)
- `TARGET_BYTES` (default: `TARGET_SECTORS*512`)
- `VG_NAME` (default: `vg_amygdala`)
- `LV_NAME` (default: `lv_root`)
- `MOUNTPOINT` (default: `/mnt/amygdala`)
- `RECOVERY_OUT` (default: `$HOME/backup/jrchung-hdd/recovered-amygdala`)

## Troubleshooting

### `fdisk` errors on loop device

The script does not depend on `fdisk` for success. `partx` + `lsblk` are used for robust loop mapping.

### LVM picks physical `/dev/sdd2` instead of image

The script uses LVM `global_filter` to allow only `${LOOPDEV}p2`, preventing accidental physical PV selection.

### `sdd-work.img` is zero bytes

Use current script version (fixed). It computes bytes explicitly and uses sudo for copy/truncate.

### Mount fails

Check:

- LV active status: `sudo lvs -a -o +devices`
- correct VG/LV names
- mount read-only with `-o ro,noload`

## Safety Guidance

- Keep source disk read-only as much as possible.
- Avoid `pvresize`, `fsck -y`, or write repairs on original media until backups are secure.
- Perform recovery operations against image files whenever possible.

## Create GitHub Repo (Local Initialization)

This directory is currently not a git repo. To initialize:

```bash
git init
git add sdd_image_recovery.sh README.md log.md
git commit -m "Add interactive sdd image recovery script and documentation"
```

Then create/push to a remote:

```bash
git branch -M main
git remote add origin <your-github-repo-url>
git push -u origin main
```

## License

Add a `LICENSE` file before publishing if you want explicit reuse terms (for example MIT).
