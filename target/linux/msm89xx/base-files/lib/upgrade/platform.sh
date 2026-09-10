#!/bin/sh

PART_NAME=firmware
REQUIRE_IMAGE_METADATA=1

RAMFS_COPY_DATA="/lib/functions.sh /lib/upgrade/common.sh /lib/upgrade/fwtool.sh /lib/upgrade/luci-add-conffiles.sh /lib/upgrade/platform.sh /lib/upgrade/tar.sh"
RAMFS_COPY_BIN="/usr/sbin/mkfs.ext4"

platform_check_image() {
	local fw_image="$1"
	local board_dir

	board_dir=$(tar tf "$fw_image" 2>/dev/null | grep -m 1 '^sysupgrade-.*/$')

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

platform_do_upgrade() {
	local tar_file="$1"
	local boot_part rootfs_part rootfs_data_part
	local board_dir

	board_dir=$(tar tf "$tar_file" 2>/dev/null | grep -m 1 '^sysupgrade-.*/$')
	board_dir=${board_dir%/}

	[ -n "$board_dir" ] || {
		echo "sysupgrade: cannot find board directory"
		return 1
	}

	boot_part=$(find_mmc_part "boot")
	rootfs_part=$(find_mmc_part "rootfs")
	rootfs_data_part=$(find_mmc_part "rootfs_data")

	[ -n "$boot_part" ] || {
		echo "sysupgrade: cannot find 'boot' partition"
		return 1
	}

	[ -n "$rootfs_part" ] || {
		echo "sysupgrade: cannot find 'rootfs' partition"
		return 1
	}

	[ -n "$rootfs_data_part" ] || {
		echo "sysupgrade: cannot find 'rootfs_data' partition"
		return 1
	}

	echo "sysupgrade: writing kernel to $boot_part"

	tar -xOf "$tar_file" "${board_dir}/kernel" 2>/dev/null |
		dd of="$boot_part" bs=4096 conv=fsync || {
			echo "sysupgrade: failed to write kernel"
			return 1
		}

	echo "sysupgrade: writing rootfs to $rootfs_part"

	tar -xOf "$tar_file" "${board_dir}/root" 2>/dev/null |
		dd of="$rootfs_part" bs=4096 conv=fsync || {
			echo "sysupgrade: failed to write rootfs"
			return 1
		}

	if [ "${SAVE_CONFIG:-1}" = "0" ]; then
		echo "sysupgrade: formatting $rootfs_data_part as ext4"

		[ -x /usr/sbin/mkfs.ext4 ] || {
			echo "sysupgrade: mkfs.ext4 not found"
			return 1
		}

		[ -b "$rootfs_data_part" ] || {
			echo "sysupgrade: $rootfs_data_part is not a block device"
			return 1
		}

		umount /overlay 2>/dev/null
		umount "$rootfs_data_part" 2>/dev/null

		mkfs.ext4 -F -L rootfs_data "$rootfs_data_part" || {
			echo "sysupgrade: failed to format rootfs_data"
			return 1
		}

		sync
		echo "sysupgrade: rootfs_data format OK"
	else
		echo "sysupgrade: keeping $rootfs_data_part"
	fi

	sync
}