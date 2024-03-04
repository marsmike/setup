curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
chmod u+x nvim.appimage
sudo mv nvim.appimage ~/bin/nvim

# FUSE Problem Fix:
# sudo add-apt-repository universe
# sudo apt install libfuse2
