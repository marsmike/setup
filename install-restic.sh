wget -O restic.bz2 https://github.com/restic/restic/releases/download/v0.9.6/restic_0.9.6_linux_amd64.bz2
bunzip2 restic.bz2
chmod +x restic
mv restic /usr/local/bin/
