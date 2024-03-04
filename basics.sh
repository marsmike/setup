#!/bin/bash

sudo apt update
sudo apt -y install git apt-transport-https ca-certificates curl build-essential docker docker-compose htop btop vim wget python3

# Handle with care .. only if AppImage is complaining about missing fuse support
# => Installs too much packages
# sudo apt install fuse libfuse2 
