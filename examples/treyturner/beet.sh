#!/usr/bin/env sh
docker run --rm -it \
  -e UMASK=0002 \
  -v /mnt/cache/appdata/beets/config:/config \
  -v /mnt/user/music:/library \
  -v /mnt/user/music-unsorted:/unsorted \
  -v /mnt/cache/downloads/Music:/incoming/sabnzbd \
  -v /mnt/user/torrents/complete/lidarr:/incoming/lidarr \
  -v /mnt/cache/downloads/Tidarr:/incoming/tidarr \
  registry.treyturner.info/treyturner/beets:v2.5.1-dev
  "$@"