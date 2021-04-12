# How to setup a kubernetes node on any netcup VPS

## Manual installation steps

### Step 1. Init and Secure System

With preconfigured root user:

```bash
# passwd / set new root password
hostnamectl set-hostname kubernetes-node
# vim /etc/hosts

adduser mike
#
adduser mike sudo
# nur bei 20.04
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
apt install docker-ce docker-ce-cli containerd.io
#
# SSH verlegen um Platz für Gitlab Port zu schaffen:
sudo sed -i -e 's/#Port 22/Port 2222/' /etc/ssh/sshd_config

sudo systemctl restart ssh
```

With new user `mike` via SSH:

```
mkdir .ssh
ssh-keygen
# echo "ssh-rsa AAAAB...3w== ssh-jowi-privat-aes" >> ~/.ssh/authorized_keys
cp ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys

sudo passwd -l root
sudo ufw allow OpenSSH
sudo ufw allow 2222
sudo ufw allow out http
sudo ufw allow out https
sudo ufw allow out 22
# allow dns queries
sudo ufw allow out 53/udp
# allow ntp systemd time syncing
sudo ufw allow out 123
sudo ufw default deny outgoing
sudo ufw default deny incoming
sudo ufw enable
```

### Partitioning

```
sudo fdisk /dev/sda
# create partition 4 and 5 with 75G and rest
sudo mke2fs /dev/sda4
sudo mke2fs /dev/sda5
echo "/dev/sda4 /var ext4 defaults 0 2"  | sudo tee -a /etc/fstab
echo "/dev/sda5 /srv ext4 defaults 0 2"  | sudo tee -a /etc/fstab
sudo mkdir /mnt/tmp
sudo mount /dev/sda4 /mnt/tmp
sudo mv /var/* /mnt/tmp
sudo mount /dev/sda4 /var
sudo mount /dev/sda5 /srv
sudo umount /mnt/tmp
```

Enable Automatic Updates

```
sudo sed -i 's/\/\/Unattended-Upgrade::Automatic-Reboot/Unattended-Upgrade::Automatic-Reboot/g' /etc/apt/apt.conf.d/50unattended-upgrades
cat <<EOF | sudo tee -a /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
```
