{
  "ignition": {
    "version": "3.4.0"
  },
  "passwd": {
    "users": [
      {
        "name": "${SETUP_USER}",
        "passwordHash": "${USER_PASSWORD_HASH}",
        "sshAuthorizedKeys": [
          "${SSH_PUBLIC_KEY}"
        ],
        "groups": [
          "wheel",
          "sudo",
          "docker"
        ]
      }
    ]
  },
  "storage": {
    "files": [
      {
        "path": "/etc/hostname",
        "mode": 420,
        "overwrite": true,
        "contents": {
          "source": "data:,${VM_NAME}%0A"
        }
      },
      {
        "path": "/etc/NetworkManager/system-connections/static.nmconnection",
        "mode": 384,
        "overwrite": true,
        "contents": {
          "source": "data:,%5Bconnection%5D%0Aid%3Dstatic-eth%0Atype%3Dethernet%0A%0A%5Bipv4%5D%0Aaddress1%3D${VM_IP}/${VM_NETMASK}%2C${VM_GATEWAY}%0Adns%3D${VM_DNS}%3B%0Anever-default%3Dfalse%0Amethod%3Dmanual%0A%0A%5Bipv6%5D%0Aaddr-gen-mode%3Deui64%0Amethod%3Dauto%0A"
        }
      },
      {
        "path": "/etc/systemd/system/rpm-ostreed.service.d/00-override.conf",
        "mode": 420,
        "overwrite": true,
        "contents": {
          "source": "data:,%5BService%5D%0AEnvironment%3D%22TimeoutStopSec%3D120s%22%0A"
        }
      },
      {
        "path": "/usr/local/bin/rebase-to-sway.sh",
        "mode": 493,
        "overwrite": true,
        "contents": {
          "source": "data:text/plain;charset=utf-8,%23%21%2Fbin%2Fbash%0Aset%20-euo%20pipefail%0ASTAMP%3D%2Fvar%2Flib%2Frebase-to-sway.done%0Aif%20%5B%20-f%20%22%24STAMP%22%20%5D%3B%20then%0A%20%20echo%20%22Rebase%20already%20completed%2C%20skipping.%22%0A%20%20exit%200%0Afi%0A%0Aecho%20%22Freeing%20%2Fboot%20space%20before%20rebase...%22%0Amount%20-o%20remount%2Crw%20%2Fboot%0Afind%20%2Fboot%2Fostree%2F%20-name%20%27initramfs-%2A.img%27%20-delete%0Aecho%20%22Freed%20%2Fboot%20space%3A%20%24%28df%20-h%20%2Fboot%20%7C%20tail%20-1%20%7C%20awk%20%27%7Bprint%20%244%7D%27%29%20available%22%0A%0A%23%20Record%20old%20BLS%20entries%20before%20rebase%20%28to%20remove%20after%29%0AOLD_ENTRIES%3D%24%28ls%20%2Fboot%2Floader%2Fentries%2F%2A.conf%202%3E%2Fdev%2Fnull%20%7C%7C%20true%29%0A%0Aecho%20%22Rebasing%20to%20Fedora%20Sway%20Atomic%20%28sericea%29...%22%0Arpm-ostree%20rebase%20--bypass-driver%20fedora%3Afedora%2F43%2Fx86_64%2Fsericea%20%3C%2Fdev%2Fnull%0A%0A%23%20Remove%20old%20FCOS%20BLS%20entries%20so%20GRUB%20cannot%20fall%20back%20to%20them%0A%23%20%28their%20initramfs%20was%20deleted%20above%3B%20keeping%20them%20causes%20the%20boot%20loop%20we%20are%20fixing%29%0Aecho%20%22Removing%20old%20FCOS%20boot%20entries...%22%0Afor%20entry%20in%20%24OLD_ENTRIES%3B%20do%0A%20%20%5B%20-f%20%22%24entry%22%20%5D%20%26%26%20rm%20-f%20%22%24entry%22%20%26%26%20echo%20%22Removed%3A%20%24entry%22%0Adone%0A%0Atouch%20%22%24STAMP%22%0Aecho%20%22Rebase%20complete.%20Rebooting...%22%0Asystemctl%20reboot%0A"
        }
      },
      {
        "path": "/usr/local/bin/setup-user-env.sh",
        "mode": 493,
        "overwrite": true,
        "contents": {
          "source": "data:text/plain;charset=utf-8,%23%21%2Fbin%2Fbash%0Aset%20-euo%20pipefail%0ASTAMP%3D%2Fvar%2Flib%2Fsetup-user-env.done%0Aif%20%5B%20-f%20%22%24STAMP%22%20%5D%3B%20then%0A%20%20echo%20%22User%20env%20setup%20already%20completed%2C%20skipping.%22%0A%20%20exit%200%0Afi%0A%0A%23%20Guard%3A%20only%20run%20on%20sericea%0Aif%20%21%20rpm-ostree%20status%202%3E%2Fdev%2Fnull%20%7C%20grep%20-q%20sericea%3B%20then%0A%20%20echo%20%22Not%20running%20sericea%20yet%20%28rebase%20may%20still%20be%20in%20progress%29.%20Skipping.%22%0A%20%20exit%200%0Afi%0A%0AUSER%3D${SETUP_USER}%0AHOME_DIR%3D%2Fhome%2F%24USER%0A%0A%23%20Wait%20for%20ostree%20boot%20to%20settle%0Asleep%2030%0A%0A%23%20Install%20chezmoi%20and%20apply%20dotfiles%0Asu%20-%20%22%24USER%22%20%3C%3C%20%27USERSCRIPT%27%0Aset%20-e%0Aif%20%5B%20%21%20-f%20%22%24HOME%2F.local%2Fbin%2Fchezmoi%22%20%5D%3B%20then%0A%20%20sh%20-c%20%22%24%28curl%20-fsLS%20get.chezmoi.io%29%22%20--%20init%20--apply%20${CHEZMOI_USER}%0A%20%20mkdir%20-p%20%24HOME%2F.local%2Fbin%0A%20%20%5B%20-f%20%22%24HOME%2Fbin%2Fchezmoi%22%20%5D%20%26%26%20mv%20%24HOME%2Fbin%2Fchezmoi%20%24HOME%2F.local%2Fbin%2Fchezmoi%0A%20%20rm%20-rf%20%24HOME%2Fbin%0Afi%0AUSERSCRIPT%0A%0Atouch%20%22%24STAMP%22%0Aecho%20%22User%20environment%20setup%20complete.%22%0A"
        }
      }
    ]
  },
  "systemd": {
    "units": [
      {
        "name": "rebase-to-sway.service",
        "enabled": true,
        "contents": "[Unit]\nDescription=Rebase Fedora CoreOS to Sway Atomic (sericea)\nConditionPathExists=!/var/lib/rebase-to-sway.done\nAfter=network-online.target rpm-ostreed.service\nRequires=network-online.target\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/rebase-to-sway.sh\nStandardOutput=journal+console\nStandardError=journal+console\nTimeoutStartSec=600\n\n[Install]\nWantedBy=multi-user.target\n"
      },
      {
        "name": "setup-user-env.service",
        "enabled": true,
        "contents": "[Unit]\nDescription=Setup user environment (chezmoi dotfiles)\nConditionPathExists=/var/lib/rebase-to-sway.done\nConditionPathExists=!/var/lib/setup-user-env.done\nAfter=network-online.target\nRequires=network-online.target\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/setup-user-env.sh\nStandardOutput=journal+console\nStandardError=journal+console\nTimeoutStartSec=300\n\n[Install]\nWantedBy=multi-user.target\n"
      },
      {
        "name": "qemu-guest-agent.service",
        "enabled": true
      }
    ]
  }
}
