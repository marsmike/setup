#!/bin/bash

sudo apt update
sudo apt -y install git apt-transport-https ca-certificates curl build-essential docker-compose htop gh vim wget python3

# Run if AppImage is complaining about missing fuse support
# sudo add-apt-repository universe
# sudo apt install libfuse2
