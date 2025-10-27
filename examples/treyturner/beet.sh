#!/usr/bin/env sh
TAG=v2.5.1

docker run --rm -it \
  -v /mnt/cache/appdata/beets/config:/config \
  -v /mnt/user/music:/library \
  -v /mnt/user/music-unsorted:/incoming/unsorted \
  -v /mnt/cache/downloads/Music:/incoming/sabnzbd \
  -v /mnt/user/torrents/complete/lidarr:/incoming/lidarr \
  -v /mnt/cache/downloads/Tidarr:/incoming/tidarr \
  ghcr.io/treyturner/beets:$TAG \
  bash -lc '"$@"' bash "$@"
