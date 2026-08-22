#!/bin/sh
# Run as root ON THE PHONE (Xiaomi Surya / POCO X3 NFC, postmarketOS).
#
# Works around this device using the generic device-qcom-sm7150 profile
# instead of a proper device-xiaomi-surya package: sets up dynamic-partition
# mapping for /dev/mapper/vendor, mounts the real vendor+persist partitions
# where hexagonrpcd expects them, and points hexagonrpcd-adsp-sensorspd at
# the device-specific sensor firmware/registry dir shipped by
# firmware-xiaomi-surya. Idempotent: safe to re-run any time, in particular
# after every `pmbootstrap flasher flash_rootfs` (which wipes all of this).
#
# Known limitation this script does NOT fix: hexagonrpcd's file-write
# support is an unfinished stub upstream (linux-msm/hexagonrpc issue #19 /
# PR #21), so the ADSP still crash-loops on SNS_REG_INIT regardless.

set -e

SUPER_PART=/dev/disk/by-partlabel/super
PERSIST_PART=/dev/disk/by-partlabel/persist
FW_DIR=/usr/share/qcom/sm7150/Xiaomi/surya

if [ "$(id -u)" != "0" ]; then
	echo "Run as root (sudo)." >&2
	exit 1
fi

if ! grep -q '^deviceinfo_super_partitions=' /etc/deviceinfo 2>/dev/null; then
	echo "==> Adding deviceinfo_super_partitions and regenerating initramfs"
	echo "deviceinfo_super_partitions=\"$SUPER_PART\"" >>/etc/deviceinfo
	mkinitfs
	echo "==> deviceinfo updated. A reboot is required before /dev/mapper/vendor exists."
	echo "    Reboot, then re-run this script."
	exit 0
fi

if [ ! -e /dev/mapper/vendor ]; then
	echo "/dev/mapper/vendor is missing even though deviceinfo_super_partitions is set." >&2
	echo "Reboot and re-run; if it's still missing check 'dmesg | grep -i dynpart'." >&2
	exit 1
fi

echo "==> Setting up vendor/vendorlower/persist mount units"
mkdir -p /mnt/vendorlower /mnt/vendor /var/lib/pmos-vendor-overlay/upper/persist /var/lib/pmos-vendor-overlay/work

cat >/etc/systemd/system/mnt-vendorlower.mount <<'EOF'
[Unit]
Description=Xiaomi Surya real vendor partition (read-only, ext4 shared_blocks)
After=dev-mapper-vendor.device
Requires=dev-mapper-vendor.device

[Mount]
What=/dev/mapper/vendor
Where=/mnt/vendorlower
Type=ext4
Options=ro

[Install]
WantedBy=local-fs.target
EOF

cat >/etc/systemd/system/mnt-vendor.mount <<'EOF'
[Unit]
Description=Vendor partition overlay (adds empty persist mountpoint on top of read-only vendor)
Requires=mnt-vendorlower.mount
After=mnt-vendorlower.mount
RequiresMountsFor=/var/lib/pmos-vendor-overlay

[Mount]
What=vendor-overlay
Where=/mnt/vendor
Type=overlay
Options=lowerdir=/mnt/vendorlower,upperdir=/var/lib/pmos-vendor-overlay/upper,workdir=/var/lib/pmos-vendor-overlay/work

[Install]
WantedBy=local-fs.target
EOF

cat >/etc/systemd/system/mnt-vendor-persist.mount <<EOF
[Unit]
Description=Android persist partition mounted under vendor (sensor calibration, etc.)
Requires=mnt-vendor.mount
After=mnt-vendor.mount

[Mount]
What=$PERSIST_PART
Where=/mnt/vendor/persist
Type=ext4
Options=defaults

[Install]
WantedBy=local-fs.target
EOF

echo "==> Setting up hexagonrpcd drop-ins"
mkdir -p /etc/systemd/system/hexagonrpcd-adsp-rootpd.service.d \
	/etc/systemd/system/hexagonrpcd-adsp-sensorspd.service.d \
	/etc/systemd/system/hexagonrpcd-sdsp.service.d

cat >/etc/systemd/system/hexagonrpcd-adsp-rootpd.service.d/override.conf <<'EOF'
[Unit]
RequiresMountsFor=/mnt/vendor/persist
EOF

cp /etc/systemd/system/hexagonrpcd-adsp-rootpd.service.d/override.conf \
	/etc/systemd/system/hexagonrpcd-sdsp.service.d/override.conf
cp /etc/systemd/system/hexagonrpcd-adsp-rootpd.service.d/override.conf \
	/etc/systemd/system/hexagonrpcd-adsp-sensorspd.service.d/override.conf

cat >/etc/systemd/system/hexagonrpcd-adsp-sensorspd.service.d/override-fwdir.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/hexagonrpcd -f /dev/fastrpc-adsp -d adsp -s -R $FW_DIR
EOF

echo "==> Reloading systemd and enabling mounts"
systemctl daemon-reload
systemctl enable --now mnt-vendorlower.mount mnt-vendor.mount mnt-vendor-persist.mount

echo "==> Granting the fastrpc user write access to the real persist sensor registry"
echo "    (it's owned by Android's uid/gid 1000, fastrpc is a distinct local user)"
chmod -R o+w /mnt/vendor/persist/sensors

systemctl restart hexagonrpcd-adsp-rootpd.service hexagonrpcd-adsp-sensorspd.service hexagonrpcd-sdsp.service

echo "==> Done. Current state:"
mount | grep -i vendor
ls -la /mnt/vendor/persist/sensors/registry/sns_reg_version
