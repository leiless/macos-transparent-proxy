#!/bin/bash
#
# Created: Oct 28, 2020.
# see: MIT License.
#

set -eu
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
    echo "$@" 1>&2
    echo -ne "$RST" 1>&2
    "$@"
}

errecho() {
    echo -ne "$RED" 1>&2
    echo -ne "[ERROR] "
    echo "$@" 1>&2
    echo -ne "$RST" 1>&2
}

is_ipv4() {
    echo "$1" | grep -Eq "^[0-9]{1,3}(\.[0-9]{1,3}){3}$"
}

config_proxy() {
    read -r -p "Enter proxy server(s): " HOST
    if [ -z "$HOST" ]; then
        errecho No host specified
        exit 1
    fi

    IPLIST=""
    for i in $HOST; do
        if ! is_ipv4 "$i"; then
            IPS="$(xx dig +short "$i")"
            if [ -z "$IPS" ]; then
                errecho "Cannot get DNS A record of '$i'"
                exit 1
            fi
            i="$IPS"
        fi
        IPLIST="$IPLIST $i"
    done

    # shellcheck disable=SC2086
    # shellcheck disable=SC2116
    IPLIST="$(echo $IPLIST)"
    FILE=proxy_ip_list.txt
    echo "$IPLIST" | tr ' ' '\n' > "$FILE"
}

enable_proxy() {
    #URL=https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt
    URL=https://cdn.jsdelivr.net/gh/17mon/china_ip_list@master/china_ip_list.txt
    NAME="$(basename "$URL")"
    xx curl -fsSL "$URL" -o "$NAME"
    # Add a trailing linefeed for later file concatenation
    echo >> "$NAME"

    cat << EOL > lan_ip_list.txt
0.0.0.0/8
10.0.0.0/8
127.0.0.0/8
169.254.0.0/16
172.16.0.0/12
192.168.0.0/16
224.0.0.0/4
240.0.0.0/4
EOL

    cat *_ip_list.txt > direct.txt
    mkdir -p /var/tmp/pf
    cp direct.txt /var/tmp/pf

    cat << EOL > /var/tmp/pf/pf.conf
#
# This pf.conf generated by pf-setup.sh
#

table <direct> persist file "/var/tmp/pf/direct.txt"
rdr pass on lo0 proto tcp from any to !<direct> -> 127.0.0.1 port 12345
pass out route-to (lo0 127.0.0.1) proto tcp from any to !<direct>

EOL

    xx sudo pfctl -e || true
    xx sudo pfctl -F all
    xx sudo pfctl -f /var/tmp/pf/pf.conf

    xx sudo pfctl -vvvs Tables
    xx sudo pfctl -vvvs nat
    xx sudo pfctl -vvvs rules
}

disable_proxy() {
    echo todo
}

show_status() {
    echo TODO
}

usage() {
    cat << EOL
Usage:
    $(basename "$0") config
    $(basename "$0") enable
    $(basename "$0") disable
    $(basename "$0") show

EOL
    exit "$1"
}

if [ $# -eq 0 ]; then
    usage 0
fi

cd "$(dirname "$0")"

case "$1" in
    "config")
        [ $# -ne 1 ] && usage 1
        xx config_proxy
    ;;
    "enable")
        [ $# -ne 1 ] && usage 1
        enable_proxy
    ;;
    "disable")
        [ $# -ne 1 ] && usage 1
        disable_proxy
    ;;
    "show")
        [ $# -ne 1 ] && usage 1
        show_status
    ;;
    *)
    usage 1
    ;;
esac

# Ask sudo privilege in advance, will cache later.
#sudo printf ""
#xx setup_pf_table "$@"
