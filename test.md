# MikroTik Backup Server

A lightweight, fully automated backup solution for **RouterOS** and **SwOS** devices.  
This script runs on any Linux host (typically a Proxmox LXC or VM) and stores all backups, logs, and device configuration files on an **SMB network share**.

## Features

- Automatic backups for:
  - RouterOS (.backup and .rsc export)
  - SwOS (.swb backup)
- Stateless design — all data lives on the SMB share
- Cleans up temporary backup files on RouterOS
- Per-device retention policy (daily / weekly / monthly)
- Automatic NAS connectivity check:
  - Detects missing SMB share
  - Attempts automatic remount
  - Aborts safely if unavailable
- Unlimited device support — add new .conf files in the SMB folder
- Designed for Proxmox LXC but works on any Debian/Ubuntu system
- Simple one-file installation and easy maintenance

---

# Installation (Debian / Ubuntu host)

These steps assume the script runs inside a Linux container or VM with access to an SMB share.

## 1. Install dependencies

    apt update
    apt install -y cifs-utils sshpass wget curl nano tzdata

## 2. Create the SMB mount directory

    mkdir -p /mnt/mikrotik-backups

## 3. Configure the SMB mount

Edit `/etc/fstab`:

    nano /etc/fstab

Add:

    //IP-SMB/mikrotik-backups  /mnt/mikrotik-backups  cifs  username=SMBUSER,password=SMBPASS,iocharset=utf8,vers=3.1.1,nofail,_netdev,uid=0,gid=0,file_mode=0777,dir_mode=0777  0  0

Mount the share:

    systemctl daemon-reload
    mount -a

Verify:

    mount | grep mikrotik-backups

## 4. Create required SMB folders

    mkdir -p /mnt/mikrotik-backups/{backups,devices,logs}

## 5. Install the backup script

Copy `mikrotik-backup.sh` to:

    /usr/local/bin/mikrotik-backup.sh

Make it executable:

    chmod +x /usr/local/bin/mikrotik-backup.sh

---

# Device Configuration

Place .conf files inside:

    /mnt/mikrotik-backups/devices/

Each file defines one device.

## Example RouterOS config (`rb4011.conf`)

    DEVICE_NAME="rb4011"
    DEVICE_TYPE="routeros"
    DEVICE_IP="10.1.254.1"
    DEVICE_USER="backup"
    DEVICE_PASS="your-password"

    RETENTION_DAILY=10
    RETENTION_WEEKLY=6
    RETENTION_MONTHLY=12

## Example SwOS config (`crs354.conf`)

    DEVICE_NAME="crs354"
    DEVICE_TYPE="swos"
    DEVICE_IP="10.1.254.2"
    DEVICE_USER="admin"
    DEVICE_PASS="swos-pass"

    RETENTION_DAILY=7
    RETENTION_WEEKLY=4
    RETENTION_MONTHLY=6

Adding a device = simply drop a .conf file.  
No script modification required.

---

# (Optional) Fix timezone for correct timestamps

Especially important in LXC containers:

    rm -f /etc/localtime
    ln -s /usr/share/zoneinfo/Europe/Amsterdam /etc/localtime

Check:

    date

---

# Testing

Run a manual backup:

    /usr/local/bin/mikrotik-backup.sh

View log output:

    cat /mnt/mikrotik-backups/logs/backup.log

---

# Scheduling (cron)

Edit cron table:

    crontab -e

Example: run daily at 01:15

    15 1 * * * /usr/local/bin/mikrotik-backup.sh >/dev/null 2>&1

---

# Folder Structure on SMB

    /mnt/mikrotik-backups/
    ├── backups/
    │   ├── rb4011/
    │   │   ├── rb4011-2025-02-26_21-30-00.backup
    │   │   └── rb4011-2025-02-26_21-30-00.rsc
    │   └── crs354/
    │       └── crs354-2025-02-26_21-31-00.swb
    ├── devices/
    │   ├── rb4011.conf
    │   └── crs354.conf
    └── logs/
        └── backup.log

---

# Retention Policy Behavior

Each device config can define:

    RETENTION_DAILY
    RETENTION_WEEKLY
    RETENTION_MONTHLY

Defaults:

    RETENTION_DAILY=7
    RETENTION_WEEKLY=4
    RETENTION_MONTHLY=12

Retention logic:

- Old daily backups older than RETENTION_DAILY become candidates  
- Weekly backups (Sunday) are preserved if within range  
- Monthly backups (1st–7th) preserved based on RETENTION_MONTHLY  
- All other excess backups are deleted  

---

# NAS Connectivity Behavior

On each run:

1. Script checks if SMB mount is available  
2. If missing → attempts mount -a  
3. If still missing → aborts safely  
4. Automatically resumes next run when NAS is online  
5. Prevents corrupt or partial backups  

---

# Adding New Devices

1. Create a .conf file in /devices/  
2. Use the example format  
3. Run the script — it is automatically included  

---

# Requirements

- Linux host (Proxmox LXC recommended)
- cifs-utils, sshpass, wget, curl, bash
- SMB-capable NAS (QNAP/Synology/Windows)
- RouterOS devices with SSH enabled
- SwOS devices with backup endpoint (backup.swb)

---

# License

MIT License — see LICENSE file.

---

# Contributing

Pull requests and feature additions are welcome.
