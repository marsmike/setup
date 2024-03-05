#!/bin/bash

sudo add-apt-repository universe
sudo apt update
sudo apt -y install git apt-transport-https ca-certificates curl build-essential docker-compose btop htop gh vim wget python3 python3-pip python3-venv zoxide ncdu tldr httpie powertop fzf bat ack dnsutils rsync jq tmux zsh

# AppImage is complaining about missing fuse support
sudo apt install libfuse2
