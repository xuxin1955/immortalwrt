#!/bin/sh
# MSM8916 eMMC sysupgrade - kernel (Android boot image) + rootfs (squashfs)

PART_NAME=firmware
REQUIRE_IMAGE_METADATA=1
RAMFS_COPY_DATA="/lib/functions.sh /lib/upgrade/common.sh /lib/upgrade/fwtool.sh /lib/upgrade/luci-add-conffiles.sh /lib/upgrade/platform.sh /lib/upgrade/tar.sh"

platform_check_image() {
    local fw_image="$1"
    local board_dir

    # Check that this is a valid sysupgrade tar archive
    board_dir=$(tar tf "$fw_image" 2>/dev/null |         grep -m 1 '^sysupgrade-.*/$')

    if [ -z "$board_dir" ]; then
        echo "Invalid sysupgrade file: $fw_image"
        return 1
    fi

    board_dir=${board_dir%/}

    # Check required sysupgrade files
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

platform_do_upgrade() {
    local tar_file="$1"
    local boot_part rootfs_part
    local board_dir=$(tar tf "$tar_file" | grep -m 1 '^sysupgrade-.*/$')
    board_dir=${board_dir%/}

    # Locate partitions by GPT label
    boot_part=$(find_mmc_part "boot")
    rootfs_part=$(find_mmc_part "rootfs")

    [ -z "$boot_part" ] && {
        echo "sysupgrade: cannot find 'boot' partition"
        return 1
    }

    [ -z "$rootfs_part" ] && {
        echo "sysupgrade: cannot find 'rootfs' partition"
        return 1
    }

    echo "sysupgrade: writing kernel to $boot_part"
    tar -xOf "$tar_file" "${board_dir}/kernel" 2>/dev/null |         dd of="$boot_part" bs=4096 conv=fsync

    echo "sysupgrade: writing rootfs to $rootfs_part"
    tar -xOf "$tar_file" "${board_dir}/root" 2>/dev/null |         dd of="$rootfs_part" bs=4096 conv=fsync

    sync
}

platform_pre_upgrade() {
    rm -fr /overlay/upper/* /overlay/upper/.* 2>/dev/null

    [ -f "$UPGRADE_BACKUP" ] &&         cp -f "$UPGRADE_BACKUP" "/overlay/upper/$BACKUP_FILE" 2>/dev/null
}
