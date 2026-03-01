#cloud-config
hostname: ${VM_NAME}
manage_etc_hosts: true
fqdn: ${VM_NAME}.${VM_SEARCHDOMAIN}

users:
  - name: ${SETUP_USER}
    groups: [wheel, docker]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    passwd: ${USER_PASSWORD_HASH}
    ssh_authorized_keys:
      - ${SSH_PUBLIC_KEY}

package_upgrade: false

# For standard Fedora, this works. For Fedora Atomic, this may fail or be ignored.
packages:
  - qemu-guest-agent
  - curl
  - git
  - vim
  - python3
  - tmux
  - zsh
  - htop
  - tree
  - jq
  - wget

write_files:
  - path: /etc/ssh/sshd_config.d/50-cloud-init.conf
    content: |
      PasswordAuthentication no
      PubkeyAuthentication yes
      PermitRootLogin no
  - path: /etc/sysctl.d/99-enable-ipv4-forwarding.conf
    content: |
      net.ipv4.conf.all.forwarding=1

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - systemctl enable sshd
  - systemctl restart sshd
  - chown -R ${SETUP_USER}:${SETUP_USER} /home/${SETUP_USER}
  - chsh -s /usr/bin/zsh ${SETUP_USER}

power_state:
  mode: reboot
  message: "Cloud-init complete. Rebooting..."
  timeout: 60
  condition: True

final_message: "VM ready. System rebooting."
