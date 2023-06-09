#!/usr/bin/env bash

set -e

# Rustup if [[ ! $(command -v rustup) ]]
if ! command -v rustup &> /dev/null
then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
fi

cargo install stylua
cargo install paru

# fnm
if ! command -v fnm &> /dev/null
then
  cargo install fnm

  export PATH="/home/st/.local/share/fnm:$PATH"
  eval "$(fnm env)"
  fnm install --lts
fi

# pnpm
if ! command -v pnpm &> /dev/null
then
  corepack enable
  corepack prepare pnpm@latest --activate
  pnpm setup
fi

# SDKMAN!
# https://sdkman.io/install
if [[ ! $(command -v sdk) ]]
then
  curl -s "https://get.sdkman.io?rcupdate=false" | bash
fi

source "${HOME}/.local/lib/sdkman/bin/sdkman-init.sh" # SDKMAN!
sdk install java
