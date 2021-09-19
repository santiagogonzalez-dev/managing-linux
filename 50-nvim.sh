#!/usr/bin/env bash

cd $HOME

git clone git@github.com:santigo-zero/Neovim.git .config/nvim

pip install pynvim
sudo npm i -g neovim

git clone https://github.com/wbthomason/packer.nvim\
 ~/.local/share/nvim/site/pack/packer/start/packer.nvim

rm $0 # Self delete