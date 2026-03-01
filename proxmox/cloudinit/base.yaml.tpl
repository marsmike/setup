#cloud-config
hostname: ${VM_NAME}
manage_etc_hosts: true
fqdn: ${VM_NAME}.${VM_SEARCHDOMAIN}

users:
  - name: ${SETUP_USER}
    groups: [sudo, docker]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    passwd: ${USER_PASSWORD_HASH}
    ssh_authorized_keys:
      - ${SSH_PUBLIC_KEY}

package_upgrade: true
packages:
  - qemu-guest-agent
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - software-properties-common
  - git
  - gh
  - vim
  - neovim
  - python3
  - python3-pip
  - python3-venv
  - tmux
  - zsh
  - htop
  - tree
  - jq
  - wget
  - unzip
  - build-essential

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
  - systemctl enable ssh
  - systemctl restart ssh
  - curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  - sh /tmp/get-docker.sh
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker ${SETUP_USER}
  - rm /tmp/get-docker.sh
  - wget -q https://github.com/bcicen/ctop/releases/download/v0.7.7/ctop-0.7.7-linux-amd64 -O /usr/local/bin/ctop
  - chmod +x /usr/local/bin/ctop
  - chown -R ${SETUP_USER}:${SETUP_USER} /home/${SETUP_USER}
  - |
    su - ${SETUP_USER} << 'MIKESCRIPT'
    set -e
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
      RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    fi
    if [ ! -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]; then
      git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $HOME/.oh-my-zsh/custom/themes/powerlevel10k
    fi
    if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
      git clone https://github.com/zsh-users/zsh-autosuggestions $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions
    fi
    if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]; then
      git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
    fi
    if [ ! -f "$HOME/.local/bin/chezmoi" ]; then
      sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply ${CHEZMOI_USER}
      mkdir -p $HOME/.local/bin
      [ -f "$HOME/bin/chezmoi" ] && mv $HOME/bin/chezmoi $HOME/.local/bin/chezmoi
      rm -rf $HOME/bin
    fi
    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
      git clone https://github.com/tmux-plugins/tpm $HOME/.tmux/plugins/tpm
    fi
    MIKESCRIPT
  - chsh -s /usr/bin/zsh ${SETUP_USER}

power_state:
  mode: reboot
  message: "Cloud-init complete. Rebooting..."
  timeout: 60
  condition: True

final_message: "VM ready. Docker + dev tools installed. System rebooting."
