#!/bin/sh
# MSM8916 eMMC sysupgrade - kernel (Android boot image) + rootfs (squashfs)
# Partition auto-detect: rootfs from cmdline, boot by Android bootimg magic

PART_NAME=firmware
REQUIRE_IMAGE_METADATA=1
RAMFS_COPY_DATA="/lib/functions.sh /lib/upgrade/common.sh /lib/upgrade/fwtool.sh /lib/upgrade/luci-add-conffiles.sh /lib/upgrade/platform.sh /lib/upgrade/tar.sh"

platform_check_image() {
    local fw_image="$1"
    local board_dir

    board_dir=$(tar tf "$fw_image" 2>/dev/null |         grep -m 1 '^sysupgrade-.*/$')

    if [ -z "$board_dir" ]; then
        echo "Invalid sysupgrade file: $fw_image"
        return 1
    fi

    board_dir=${board_dir%/}

    if ! tar tf "$fw_image" 2>/dev/null | grep -q "^${board_dir}/CONTROL$"; then
        echo "Invalid sysupgrade file: missing CONTROL"
        return 1
    fi

    if ! tar tf "$fw_image" 2>/dev/null | grep -q "^${board_dir}/kernel$"; then
        echo "Invalid sysupgrade file: missing kernel"
        return 1
    fi

    if ! tar tf "$fw_image" 2>/dev/null | grep -q "^${board_dir}/root$"; then
        echo "Invalid sysupgrade file: missing root"
        return 1
    fi

    return 0
}

find_boot_part() {
    local dev magic
    for dev in /dev/mmcblk0p*; do
        [ -b "$dev" ] || continue
        magic=$(dd if="$dev" bs=4 count=1 2>/dev/null | hexdump -e '1/4 "%08x"')
        [ "$magic" = "52444e41" ] && { echo "$dev"; return; }
    done
}

platform_do_upgrade() {
    local tar_file="$1"
    local rootfs_part boot_part board_dir tmpdir
    local ksize rsize v1 v2

    rootfs_part=$(cat /proc/cmdline | tr ' ' '\n' | grep '^root=' | cut -d= -f2)
    [ -b "$rootfs_part" ] || { echo "sysupgrade: rootfs not found from cmdline"; return 1; }

    boot_part=$(find_boot_part)
    [ -b "$boot_part" ] || boot_part="/dev/mmcblk0p12"
    [ -b "$boot_part" ] || { echo "sysupgrade: boot part not found"; return 1; }

    echo "sysupgrade: boot=$boot_part rootfs=$rootfs_part"

    board_dir=$(tar tf "$tar_file" | grep -m 1 '^sysupgrade-.*/$')
    board_dir=${board_dir%/}
    [ -z "$board_dir" ] && { echo "sysupgrade: bad tar structure"; return 1; }

    tmpdir=$(mktemp -d)
    [ -d "$tmpdir" ] || { echo "sysupgrade: cannot create tmpdir"; return 1; }

    echo "sysupgrade: extracting kernel..."
    if ! tar -xOf "$tar_file" "${board_dir}/kernel" > "$tmpdir/kernel" 2>/tmp/tar_err; then
        echo "sysupgrade: kernel extract FAILED:"; cat /tmp/tar_err
        rm -rf "$tmpdir"; return 1
    fi
    echo "sysupgrade: extracting root..."
    if ! tar -xOf "$tar_file" "${board_dir}/root" > "$tmpdir/root" 2>/tmp/tar_err; then
        echo "sysupgrade: root extract FAILED:"; cat /tmp/tar_err
        rm -rf "$tmpdir"; return 1
    fi

    ksize=$(wc -c < "$tmpdir/kernel")
    rsize=$(wc -c < "$tmpdir/root")
    [ "$ksize" -eq 0 ] && { echo "sysupgrade: kernel empty"; rm -rf "$tmpdir"; return 1; }
    [ "$rsize" -eq 0 ] && { echo "sysupgrade: root empty"; rm -rf "$tmpdir"; return 1; }
    echo "sysupgrade: kernel=$ksize root=$rsize"

    echo "sysupgrade: writing kernel to $boot_part"
    if ! dd if="$tmpdir/kernel" of="$boot_part" bs=4096 conv=fsync 2>/tmp/dd_err; then
        echo "sysupgrade: kernel write FAILED:"; cat /tmp/dd_err
        rm -rf "$tmpdir"; return 1
    fi

    echo "sysupgrade: writing rootfs to $rootfs_part"
    if ! dd if="$tmpdir/root" of="$rootfs_part" bs=4096 conv=fsync 2>/tmp/dd_err; then
        echo "sysupgrade: rootfs write FAILED:"; cat /tmp/dd_err
        rm -rf "$tmpdir"; return 1
    fi

    echo "sysupgrade: verifying..."
    v1=$(dd if="$boot_part" bs=4 count=1 2>/dev/null | hexdump -e '1/4 "%08x"')
    v2=$(dd if="$rootfs_part" bs=4 count=1 2>/dev/null | hexdump -e '1/4 "%08x"')
    echo "sysupgrade: boot magic=$v1 rootfs magic=$v2"

    sync
    rm -rf "$tmpdir"
    echo "sysupgrade: done"
}

platform_pre_upgrade() {
    rm -fr /overlay/upper/* /overlay/upper/.* 2>/dev/null

    [ -f "$UPGRADE_BACKUP" ] &&         cp -f "$UPGRADE_BACKUP" "/overlay/upper/$BACKUP_FILE" 2>/dev/null
}