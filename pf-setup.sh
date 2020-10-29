#!/bin/bash
#
# Created: Oct 28, 2020.
# see: MIT License.
#

set -eu
#set -x

# see: https://misc.flogisoft.com/bash/tip_colors_and_formatting
GRN="\033[92m"
RST="\033[0m"

# tc stands for trace command, useful for presentation and debugging.
tc() {
    echo -en "+ $GRN"
    echo -n $@
    echo -e "$RST"
    "$@"
}

setup_pf_table() {
    #URL=https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt
    URL=https://cdn.jsdelivr.net/gh/17mon/china_ip_list@master/china_ip_list.txt
    NAME="$(basename "$URL")"
    tc curl -fsSL "$URL" -o "$NAME"
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

    rm -f proxy_ip_list.txt
    for IP in "$@"; do
        echo $IP >> proxy_ip_list.txt
    done

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

    tc sudo pfctl -e || true
    tc sudo pfctl -F all
    tc sudo pfctl -f /var/tmp/pf/pf.conf

    tc sudo pfctl -vvvs Tables
    tc sudo pfctl -vvvs nat
    tc sudo pfctl -vvvs rules
}

is_ipv4() {
    if [ $# -ne 1 ]; then
        echo "ERROR: expected one argument"
        return 1
    fi
    echo "$1" | grep -Eq "^[0-9]{1,3}(\.[0-9]{1,3}){3}$"
}

usage() {
    cat << EOL
Usage:
    $(basename "$0") IPv4...

EOL
    exit "$1"
}

if [ $# -eq 0 ]; then
    usage 1
fi

# see: https://stackoverflow.com/questions/2761723/what-is-the-difference-between-and-in-shell-scripts
for IP in "$@"; do
    if ! is_ipv4 "$IP"; then
        usage 1
    fi
done

cd "$(dirname "$0")"

tc setup_pf_table "$@"

