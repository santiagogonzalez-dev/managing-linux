#!/usr/bin/env bash

podman pull docker.io/mysql:latest \
   registry.opensuse.org/opensuse/microos-docserv:latest \
   registry.opensuse.org/opensuse/distrobox-packaging:latest \
   quay.io/fedora-ostree-desktops/kinoite:39 \
   docker.io/excalidraw/excalidraw:latest
