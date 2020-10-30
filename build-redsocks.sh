#!/bin/bash
#
# see: MIT License.
#

set -euf
#set -x

# see:
#   https://misc.flogisoft.com/bash/tip_colors_and_formatting
#   https://gist.github.com/leiless/408b978965fc76b3c41b837811a475d2
if [ -t 2 ]; then
    RED="$(tput setaf 9)"
    GRN="$(tput setaf 10)"
    RST="$(tput sgr0)"
else
    RED=""
    GRN=""
    RST=""
fi

# xx used for tracing command, useful for presentation and debugging.
# Trace output will be write to stderr, just as set -x.
xx() {
    echo -ne "$RED+ $GRN" 1>&2
    echo -n "$@" 1>&2
    echo -e "$RST" 1>&2
    "$@"
}

cd "$(dirname "$0")"

xx rm -rf redsocks
xx git clone --depth 1 https://github.com/semigodking/redsocks

xx rm -f redsocks2/redsocks2-debug
xx rm -f redsocks2/redsocks2-release
xx mkdir -p redsocks2

xx pushd redsocks
xx git apply ../patches/patch_redsocks.diff
xx make debug DISABLE_SHADOWSOCKS=true ENABLE_HTTPS_PROXY=true -j$(sysctl -n hw.ncpu)
xx mv redsocks2 ../redsocks2/redsocks2-debug
xx make clean
xx make release DISABLE_SHADOWSOCKS=true ENABLE_HTTPS_PROXY=true -j$(sysctl -n hw.ncpu)
xx mv redsocks2 ../redsocks2/redsocks2-release
xx popd

xx rm -rf redsocks

