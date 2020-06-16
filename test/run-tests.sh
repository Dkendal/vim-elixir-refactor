#!/bin/sh
set -eu

make build

./test/vim.sh --headless -c "UpdateRemotePlugins" -c "q"
./test/vim.sh --headless -c "Vader!test/**/*.vader"
