#!/bin/bash

set -euf
#set -x

cd "$(dirname "$0")"

rm -rf redsocks
rm -f redsocks2
git clone --depth 1 https://github.com/semigodking/redsocks

pushd redsocks
git apply ../patch_redsocks.diff
make DISABLE_SHADOWSOCKS=true ENABLE_HTTPS_PROXY=true -j$(sysctl -n hw.ncpu)
mv redsocks2 ..
popd

