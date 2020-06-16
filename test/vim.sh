#!/bin/sh
set -eu
NVIM_RPLUGIN_MANIFEST=./test/rplugin.vim vim -Nu ./test/vimrc $@
