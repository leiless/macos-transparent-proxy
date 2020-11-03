#!/bin/bash
#
# Created: Oct 28, 2020.
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
    echo "$@" 1>&2
    echo -ne "$RST" 1>&2
    "$@"
}

errecho() {
    echo -ne "$RED" 1>&2
    echo -n "[ERROR] " 1>&2
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
            # Filter out IPv6 if any
            IPS="$(echo "$IPS" | grep -v :)"
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
    mkdir -p pf
    FILE="pf/proxy_ip_list.txt"
    echo "$IPLIST" | tr ' ' '\n' > "$FILE"
    echo "Saved $IPLIST to $FILE"
}

gh_latest_release() {
    xx curl -fsSL "https://api.github.com/repos/$1/releases/latest" | grep '"tag_name":' | cut -d'"' -f4
}

map_arch() {
	T="$(uname -m)"
	if [ "$T" = "x86_64" ]; then
		T=amd64
	fi
	echo $T
}

setup_coredns() {
    REPO="leiless/dnsredir"
    VER="$(xx gh_latest_release $REPO)"
    FILE="coredns_dnsredir-darwin-$(map_arch).zip"
    URL="https://github.com/$REPO/releases/download/$VER/$FILE"

    xx mkdir -p coredns
    xx pushd coredns
    BIN="$(basename "$FILE" .zip)"
    if [ ! -f "$BIN" ]; then
        xx wget "$URL" -O "$FILE"
        xx yes | xx unzip -q "$FILE"
        xx rm -f "$FILE"
        xx rm -f coredns
        xx ln -s "$BIN" coredns
    fi
    xx touch direct.conf
    xx sudo ./coredns > coredns.log 2>&1 &
    xx popd
}

setup_network() {
    INF="$(xx route -n get default | grep interface: | awk '{print $2}')"
    DEV="$(xx networksetup -listnetworkserviceorder | grep " $INF)" -B 1 | head -1 | cut -d' ' -f2-)"
    if [ -z "$DEV" ]; then
        errecho "Network interface $INF seems unstable."
        exit 1
    fi
    xx networksetup -setdnsservers "$DEV" 127.0.0.1
    xx networksetup -setv6off "$DEV"
}

# Ask sudo in advance
ask_sudo() {
    sudo printf ""
}

setup_redsocks2() {
    #redsocks2/redsocks2-release -c release.conf
    errecho TODO: setup redsocks2
}

setup_pf() {
    FILE="pf/proxy_ip_list.txt"
    if [ ! -f "$FILE" ]; then
        errecho "Please run '$(basename "$0") config' first"
        exit 1
    fi

    #URL=https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt
    URL=https://cdn.jsdelivr.net/gh/17mon/china_ip_list@master/china_ip_list.txt
    NAME="pf/$(basename "$URL")"
    if [ ! -f "$NAME" ]; then
        xx curl -fsSL "$URL" -o "$NAME"
        # Add a trailing linefeed for later file concatenation
        echo >> "$NAME"
    fi

    cat << EOL > pf/lan_ip_list.txt
0.0.0.0/8
10.0.0.0/8
127.0.0.0/8
169.254.0.0/16
172.16.0.0/12
192.168.0.0/16
224.0.0.0/4
240.0.0.0/4
EOL

    find pf -type f -name '*_ip_list.txt' -exec cat {} \; > pf/direct.txt

    mkdir -p /var/tmp/pf
    cp pf/direct.txt /var/tmp/pf

    cat << EOL > /var/tmp/pf/pf.conf
#
# This pf.conf generated by pf-setup.sh
#

table <direct> persist file "/var/tmp/pf/direct.txt"
rdr pass on lo0 proto tcp from any to !<direct> -> 127.0.0.1 port 1079
pass out route-to (lo0 127.0.0.1) proto tcp from any to !<direct>

EOL

    xx sudo pfctl -e || true
    xx sudo pfctl -F all
    xx sudo pfctl -f /var/tmp/pf/pf.conf

    xx sudo pfctl -vvvs Tables
    xx sudo pfctl -vvvs nat
    xx sudo pfctl -vvvs rules

    echo "Proxy server(s): $(cat pf/proxy_ip_list.txt | tr '\n' ' ')"
}

start_proxy() {
    FILE="pf/proxy_ip_list.txt"
    if [ ! -f "$FILE" ]; then
        errecho "Please run '$(basename "$0") config' first"
        exit 1
    fi

    if xx is_pf_enabled; then
        errecho "Transparent proxy seems already started, please restart proxy or issue a bug report if it's not the case."
        exit 1
    fi

    xx setup_redsocks2
    xx setup_pf
    # CoreDNS should be setup after pf setup is done.
    xx setup_coredns
    xx setup_network

    xx curl -4svL https://ifconfig.co/json | python -m json.tool
}

# Essentially reverse operation of start_proxy
stop_proxy() {
    FILE="pf/proxy_ip_list.txt"
    if [ ! -f "$FILE" ]; then
        errecho "Config file not found, skip disable proxy."
        exit 1
    fi

    ask_sudo

    INF="$(xx route -n get default | grep interface: | awk '{print $2}')"
    DEV="$(xx networksetup -listnetworkserviceorder | grep " $INF)" -B 1 | head -1 | cut -d' ' -f2-)"
    if [ -z "$DEV" ]; then
        errecho "Network interface $INF seems unstable."
        exit 1
    fi
    xx networksetup -setdnsservers "$DEV" empty
    xx networksetup -setv6automatic "$DEV"

    xx sudo killall -KILL coredns || true

    xx sudo pfctl -d || true
    xx sudo pfctl -F all

    xx sudo killall -KILL redsocks2 || true

    xx curl -4svL https://ifconfig.co/json | python -m json.tool || true
}

is_pf_enabled() {
    sudo pfctl -s info 2> /dev/null | grep -q "^Status: Enabled "
}

show_status() {
    ask_sudo

    if xx pgrep -q coredns; then
        echo "coredns is running."
    else
        echo "coredns is not running."
    fi
    echo

    INF="$(xx route -n get default | grep interface: | awk '{print $2}')"
    DEV="$(xx networksetup -listnetworkserviceorder | grep " $INF)" -B 1 | head -1 | cut -d' ' -f2-)"

    if [ -z "$DEV" ]; then
        errecho "Network interface $INF seems unstable."
        exit 1
    fi
    WIFI_NAME=$(xx networksetup -getairportnetwork "$INF" | awk -F 'Current Wi-Fi Network: ' '/Current Wi-Fi Network: /{print $2}')
    if [ ! -z "$WIFI_NAME" ]; then
        echo "$DEV($INF) SSID: $WIFI_NAME"
    fi
    xx networksetup -getdnsservers "$DEV"
    echo

    if [ "$(xx ifconfig "$INF" | grep -E "\sinet6\s" | grep -v "%$INF\s" | grep -Ec "\sinet6\s")" -ne 0 ]; then
        echo "$DEV seems have IPv6 access, ${RED}need manual confirmation$RST."
    else
        echo "$DEV have no IPv6 access."
    fi
    echo

    if xx pgrep -q redsocks; then
        echo "redsocks2 is running."
    else
        echo "redsocks2 is not running."
    fi
    echo

    FILE="pf/proxy_ip_list.txt"
    if [ -f "$FILE" ]; then
        echo "Proxy server(s): $(cat "$FILE" | tr '\n' ' ')"
        echo
    fi

    PROTO_ADDR_PID="$(xx netstat -anvp tcp | grep -E "\sLISTEN\s" | awk '{ print $1, $4, $9 }' | grep -E "\.1080\s" || true)"
    if [ -z "$PROTO_ADDR_PID" ]; then
        echo "There is no process listening at port 1080 on TCP protocol."
    else
        PROTO="$(echo "$PROTO_ADDR_PID" | awk '{ print $1 }')"
        ADDR="$(echo "$PROTO_ADDR_PID" | awk '{ print $2 }')"
        PID="$(echo "$PROTO_ADDR_PID" | awk '{ print $3 }')"
        NAME="$(basename "$(ps awx | awk "\$1 == $PID { print \$5 }")")"
        echo "$NAME (pid = $PID) is listening at $ADDR on $PROTO."
    fi
    echo

    if xx is_pf_enabled; then
        echo "pf is enabled."
    else
        echo "pf is ${RED}disabled$RST."
    fi
    echo

    xx sudo pfctl -vvvs Tables
    echo
    xx sudo pfctl -vvvs rules
    echo
    xx sudo pfctl -vvvs nat
}

usage() {
    cat << EOL
Usage:
    $(basename "$0") config
    $(basename "$0") start
    $(basename "$0") stop
    $(basename "$0") restart
    $(basename "$0") show

EOL
    exit "$1"
}

if [ "$(uname -s)" != Darwin ]; then
    errecho "This script only valid in macOS."
    exit 1
fi

if [ $# -eq 0 ]; then
    usage 0
fi

cd "$(dirname "$0")"

case "$1" in
    "config")
        [ $# -ne 1 ] && usage 1
        xx config_proxy
    ;;
    "start")
        [ $# -ne 1 ] && usage 1
        xx start_proxy
    ;;
    "stop")
        [ $# -ne 1 ] && usage 1
        xx stop_proxy
        ;;
    "restart")
        [ $# -ne 1 ] && usage 1
        xx stop_proxy
        xx start_proxy
        ;;
    "show")
        [ $# -ne 1 ] && usage 1
        xx show_status
    ;;
    *)
    usage 1
    ;;
esac
