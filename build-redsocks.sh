#!/bin/bash

set -euf
#set -x

cd "$(dirname "$0")"

rm -rf redsocks
rm -f redsocks2
rm -f redsocks2-debug
git clone --depth 1 https://github.com/semigodking/redsocks

pushd redsocks
git apply ../patch_redsocks.diff
make debug DISABLE_SHADOWSOCKS=true ENABLE_HTTPS_PROXY=true -j$(sysctl -n hw.ncpu)
mv redsocks2 ../redsocks2-debug
make clean
make release DISABLE_SHADOWSOCKS=true ENABLE_HTTPS_PROXY=true -j$(sysctl -n hw.ncpu)
mv redsocks2 ../redsocks2
popd

