#!/bin/sh

# docker rm -f $(docker ps -qa)
# docker rmi -f $(docker images -q)
# docker volume rm $(docker volume ls -q)
docker stop $(docker ps -qa)
docker system prune --all --volumes --force # better use docker native cli 
for mount in $(mount | egrep '/var/lib/kubelet(.*)type (tmpfs|ceph)' | awk '{ print $3 }') /var/lib/kubelet /var/lib/rancher; do umount $mount; done
cleanupdirs="/etc/ceph /etc/cni /etc/kubernetes /opt/cni /opt/rke /run/secrets/kubernetes.io /run/calico /run/flannel /var/lib/calico /var/lib/etcd /var/lib/cni /var/lib/kubelet /var/lib/rancher/rke/log /var/log/containers /var/log/pods /var/run/calico"
for dir in $cleanupdirs; do
  echo "Removing $dir"
  rm -rf $dir
done
cleanupinterfaces="flannel.1 cni0 tunl0"
for interface in $cleanupinterfaces; do
  echo "Deleting $interface"
  ip link delete $interface
done
if [ "$1" = "flush" ]; then
  echo "Parameter flush found, flushing all iptables"
  iptables -F -t nat
  iptables -X -t nat
  iptables -F -t mangle
  iptables -X -t mangle
  iptables -F
  iptables -X
  /etc/init.d/docker restart
else
  echo "Parameter flush not found, iptables not cleaned"
fi
