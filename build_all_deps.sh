#!/bin/sh

set -euo pipefail

if [ -z "$(ls -A deps/raylib)" ]; then
  echo "Error: deps/raylib is empty. Make sure you've run git submodule update --init --recursive"
  exit
fi

## Build raylib
pushd deps/raylib/
git checkout 4.2.0
rm -rf build
mkdir build
cd build
cmake ..
make -j4
popd
