curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
chmod u+x nvim.appimage
mkdir -p ~/.local/bin && mv nvim.appimage ~/.local/bin/nvim

# FUSE Problem Fix:
# sudo add-apt-repository universe
# sudo apt install libfuse2
