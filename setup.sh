#!/bin/sh

VIMRC=$HOME/.vimrc
VUNDLE=$HOME/.vim/bundle/Vundle.vim
LOCAL_VIMRC="$(pwd)/.vimrc"

if [ -L "$VIMRC" ]; then
    echo "Found existing $VIMRC, moving it to $VIMRC.old"
    rm $VIMRC # $VIMRC.old
fi

ln -s $LOCAL_VIMRC $VIMRC

if [ ! -d "$VUNDLE" ]; then
    git clone https://github.com/VundleVim/Vundle.vim.git $VUNDLE
fi

vim +PluginInstall +qall

