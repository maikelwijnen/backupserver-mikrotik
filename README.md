# backupserver-mikrotik
A Linux script that, based on files on an SMB share, backs up RouterOS and SwitchOS and stores the files on the SMB share

# How to install on a Ubuntu 12 / 13 system

## ⚙️Ubuntu
### 1. Install dependency's
```
apt update
apt install -y cifs-utils sshpass wget curl nano tzdata
```

### 2. Create folders (part 1)
```
mkdir -p /mnt/mikrotik-backups 
```

### 3. Connect SMB
```
nano /etc/fstab
```

```
//IP-SMB/mikrotik-backups  /mnt/mikrotik-backups  cifs  username=SMBUSER,password=SMBPASS,iocharset=utf8,vers=3.0,nofail,_netdev,uid=0,gid=0,file_mode=0777,dir_mode=0777  0  0
```

### 4. Mount the smb-folder
```
systemctl daemon-reload
mount -a
```

### 5. Create folders (part 2)
```
mkdir -p /mnt/mikrotik-backups/{backups,devices,logs}
```

### 6. Install script
```
copy file mikrotik-backup.sh to folder /usr/local/bin/
```

### 7. Make script executable
```
chmod +x /usr/local/bin/mikrotik-backup.sh
```

## 📂SMB 
### 8. Copy and modify conf files by placing them in the smbfolder \devices

## ⚙️Ubuntu 
### 9. Test backupserver by run
```
/usr/local/bin/mikrotik-backup.sh
```
### 10. Schedule the backup
```
crontab -e
```
and add a cron-job for example run every day at 01:15
```
15 1 * * * /usr/local/bin/mikrotik-backup.sh >/dev/null 2>&1
```
