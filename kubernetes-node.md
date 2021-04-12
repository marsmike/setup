# How to setup a kubernetes node on a Netcup VPS

## Step 1: Init and Secure System

With preconfigured root user:

```bash
# passwd / set new root password
hostnamectl set-hostname kubernetes-node
# vim /etc/hosts, modify FQDN

adduser mike
#
adduser mike sudo
# nur bei 20.04
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
apt install docker-ce docker-ce-cli containerd.io
adduser mike docker

#
# SSH verlegen um Platz für Gitlab Port zu schaffen:
sudo sed -i -e 's/#Port 22/Port 2222/' /etc/ssh/sshd_config

sudo systemctl restart ssh
```

With new user `mike` via SSH:

```bash
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

Copy id_rsa and id_rsa.pub from ~/.ssh to your development system and secure it.
Then try to connect with the new key. If it works you can secure SSHD further:

```bash
sed -i "s/.*RSAAuthentication.*/RSAAuthentication yes/g" /etc/ssh/sshd_config
sed -i "s/.*PubkeyAuthentication.*/PubkeyAuthentication yes/g" /etc/ssh/sshd_config
sed -i "s/.*PasswordAuthentication.*/PasswordAuthentication no/g" /etc/ssh/sshd_config
sed -i "s/.*AuthorizedKeysFile.*/AuthorizedKeysFile\t\.ssh\/authorized_keys/g" /etc/ssh/sshd_config
sed -i "s/.*PermitRootLogin.*/PermitRootLogin no/g" /etc/ssh/sshd_config
service sshd restart
```

### Partitioning

```bash
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

### Enable Automatic Updates

```bash
sudo sed -i 's/\/\/Unattended-Upgrade::Automatic-Reboot/Unattended-Upgrade::Automatic-Reboot/g' /etc/apt/apt.conf.d/50unattended-upgrades
cat <<EOF | sudo tee -a /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
```

## Step 2: Create the Cluster

### Preparation

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo sysctl --system

cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--feature-gates="IPv6DualStack=true"
EOF

cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
```

```bash
sudo systemctl enable docker
sudo systemctl restart docker
sudo ufw allow 6443
sudo ufw allow out to 172.18.0.0/24
sudo ufw allow out to 172.18.1.0/24
sudo ufw allow out to fc00::/64
sudo ufw allow out to fc01::/110
sudo ufw allow in from 172.18.0.0/24
sudo ufw allow in from 172.18.1.0/24
sudo ufw allow in from fc00::/64
sudo ufw allow in from fc01::/110
```

### Install kubelet, kubeadm, kubectl and helm packages

```bash
sudo apt-get update && sudo apt-get upgrade
sudo apt-get install -y apt-transport-https curl mc ipvsadm
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

sudo snap install helm --classic
helm repo add stable https://charts.helm.sh/stable
helm repo update
```

Bash Completion https://kubernetes.io/de/docs/tasks/tools/install-kubectl/

```bash
echo 'source <(kubectl completion bash)' >>~/.bashrc
```

Kubeadm Setup

```bash
cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta2
featureGates:
  IPv6DualStack: true
kind: ClusterConfiguration
kubernetesVersion: 1.21.0
networking:
  serviceSubnet: "172.18.1.0/24,fc01::/110"
  podSubnet: "172.18.0.0/24,fc00::/64"
  dnsDomain: "cluster.local"
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ipvs
EOF
sudo kubeadm init --config kubeadm-config.yaml
```

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) \$HOME/.kube/config

kubectl taint nodes --all node-role.kubernetes.io/master-

# edit /etc/kubernetes/manifests/kube-apiserver.yaml
# add ServerSideApply=false to --feature-gate parameter
```