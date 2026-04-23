#!/usr/bin/env bash
set -u

# Interactive, step-by-step recovery helper for /dev/sdd imaging and LVM mount attempts.
# It prompts before each action and lets you skip steps.

DEVICE="${DEVICE:-/dev/sdd}"
WORKDIR="${WORKDIR:-$HOME/backup/jrchung-hdd/recovery-sdd}"
CLIPPED_IMG="${CLIPPED_IMG:-sdd-clipped.img}"
CLIPPED_LOG="${CLIPPED_LOG:-sdd-clipped.log}"
WORK_IMG="${WORK_IMG:-sdd-work.img}"
TARGET_SECTORS="${TARGET_SECTORS:-156301488}"
TARGET_BYTES="${TARGET_BYTES:-$((TARGET_SECTORS*512))}"
VG_NAME="${VG_NAME:-vg_amygdala}"
LV_NAME="${LV_NAME:-lv_root}"
MOUNTPOINT="${MOUNTPOINT:-/mnt/amygdala}"
RECOVERY_OUT="${RECOVERY_OUT:-$HOME/backup/jrchung-hdd/recovered-amygdala}"
LOOPDEV_FILE="${LOOPDEV_FILE:-$WORKDIR/.loopdev}"

CLIPPED_PATH="$WORKDIR/$CLIPPED_IMG"
WORK_PATH="$WORKDIR/$WORK_IMG"
CLIPPED_LOG_PATH="$WORKDIR/$CLIPPED_LOG"

say() {
  printf '%s\n' "$*"
}

confirm() {
  local prompt="$1"
  while true; do
    read -r -p "$prompt [y/N/q]: " ans
    case "$ans" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO|"") return 1 ;;
      q|Q|quit|QUIT) say "Quitting."; exit 0 ;;
      *) say "Please answer y, n, or q." ;;
    esac
  done
}

run_step() {
  local title="$1"
  local cmd="$2"

  say ""
  say "== $title =="
  say "Command:"
  say "$cmd"

  if ! confirm "Run this command?"; then
    say "Skipped: $title"
    return 0
  fi

  bash -lc "$cmd"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    say "Command failed (exit $rc)."
    if confirm "Continue to next step anyway?"; then
      return 0
    fi
    say "Stopping due to command failure."
    exit $rc
  fi
}

ensure_loopdev() {
  if [[ -n "${LOOPDEV:-}" ]]; then
    return 0
  fi

  if [[ -f "$LOOPDEV_FILE" ]]; then
    LOOPDEV="$(<"$LOOPDEV_FILE")"
    if [[ -n "$LOOPDEV" ]]; then
      say "Using loop device from $LOOPDEV_FILE: $LOOPDEV"
      return 0
    fi
  fi

  read -r -p "Loop device not known. Enter loop device (example /dev/loop0), or leave blank to skip: " LOOPDEV
  if [[ -z "$LOOPDEV" ]]; then
    say "No loop device provided; skipping loop-dependent step."
    return 1
  fi
  return 0
}

say "Recovery helper configuration:"
say "  DEVICE=$DEVICE"
say "  WORKDIR=$WORKDIR"
say "  CLIPPED_IMG=$CLIPPED_IMG"
say "  WORK_IMG=$WORK_IMG"
say "  TARGET_SECTORS=$TARGET_SECTORS"
say "  TARGET_BYTES=$TARGET_BYTES"
say "  VG_NAME=$VG_NAME"
say "  LV_NAME=$LV_NAME"
say "  MOUNTPOINT=$MOUNTPOINT"
say "  RECOVERY_OUT=$RECOVERY_OUT"

run_step "Create working directory" \
  "mkdir -p '$WORKDIR' && ls -ld '$WORKDIR'"

run_step "(Optional) Unmount ext3 partition before imaging" \
  "sudo umount '${DEVICE}1' || true"

run_step "Create clipped image (fast pass)" \
  "sudo ddrescue -f -n '$DEVICE' '$CLIPPED_PATH' '$CLIPPED_LOG_PATH'"

run_step "Retry bad sectors (3 retries)" \
  "sudo ddrescue -d -r3 '$DEVICE' '$CLIPPED_PATH' '$CLIPPED_LOG_PATH'"

run_step "Create working copy from clipped image" \
  "sudo cp --reflink=auto '$CLIPPED_PATH' '$WORK_PATH'"

run_step "Pad working image to expected historical PV size" \
  "sudo truncate -s '$TARGET_BYTES' '$WORK_PATH' && ls -lh '$WORK_PATH'"

say ""
say "== Attach loop device =="
say "Command:"
say "sudo losetup -Pf --read-only --show '$WORK_PATH'"
if confirm "Run this command?"; then
  LOOPDEV="$(sudo losetup -Pf --read-only --show "$WORK_PATH")"
  rc=$?
  if [[ $rc -ne 0 || -z "$LOOPDEV" ]]; then
    say "Failed to attach loop device."
    if ! confirm "Continue to next step anyway?"; then
      exit 1
    fi
  else
    printf '%s\n' "$LOOPDEV" > "$LOOPDEV_FILE"
    say "Attached: $LOOPDEV (saved in $LOOPDEV_FILE)"
  fi
else
  say "Skipped: Attach loop device"
fi

if ensure_loopdev; then
  run_step "Create partition mappings on loop device" \
    "sudo partx -av '$LOOPDEV' || true"

  run_step "Inspect loop partitions/filesystems" \
    "sudo lsblk -f '$LOOPDEV' && echo '---' && ls -l '${LOOPDEV}'p* 2>/dev/null || true"
fi

if ensure_loopdev; then
  run_step "Scan and activate LVM from loop image only (partial mode)" \
    "sudo lvm pvscan --cache --activate ay --config \"devices { global_filter=[ \\\"a|${LOOPDEV}p2|\\\", \\\"r|.*|\\\" ] }\" && sudo lvm vgchange -ay -P '$VG_NAME' --config \"devices { global_filter=[ \\\"a|${LOOPDEV}p2|\\\", \\\"r|.*|\\\" ] }\" && sudo lvm lvs -a -o +devices --config \"devices { global_filter=[ \\\"a|${LOOPDEV}p2|\\\", \\\"r|.*|\\\" ] }\""
fi

run_step "Mount LV read-only (noload)" \
  "sudo mkdir -p '$MOUNTPOINT' && sudo mount -o ro,noload '/dev/$VG_NAME/$LV_NAME' '$MOUNTPOINT'"

run_step "Copy recovered data out with rsync" \
  "mkdir -p '$RECOVERY_OUT' && sudo rsync -aHAX --info=progress2 --ignore-errors '$MOUNTPOINT/' '$RECOVERY_OUT/'"

run_step "Cleanup: unmount, deactivate VG" \
  "sudo umount '$MOUNTPOINT' || true; sudo vgchange -an '$VG_NAME' || true"

if ensure_loopdev; then
  run_step "Cleanup: detach loop device" \
    "sudo losetup -d '$LOOPDEV'"
fi

say ""
say "Script finished."
