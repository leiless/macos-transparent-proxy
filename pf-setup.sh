#!/bin/bash

set -eu
#set -x

fix_cwd() {
    cd "$(dirname "$0")"
}

generate_direct_pf_table() {
    #URL=https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt
    URL=https://cdn.jsdelivr.net/gh/17mon/china_ip_list@master/china_ip_list.txt
    NAME="$(basename "$URL")"
    curl -fsSL "$URL" -o "$NAME"
    # Add a trailing linefeed
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
}

is_ipv4() {
    if [ $# -ne 1 ]; then
        echo "ERROR: expected one argument"
        return 1
    fi
    echo "$1" | grep -Eq "^[0-9]{1,3}(\.[0-9]{1,3}){3}$"
}

if [ $# -eq 0 ]; then
    cat << EOL
Usage:
    $(basename "$0") IPv4...
EOL
    exit 1
fi

# see: https://stackoverflow.com/questions/2761723/what-is-the-difference-between-and-in-shell-scripts
for IP in "$@"; do
    is_ipv4 "$IP"
done

fix_cwd
generate_direct_pf_table "$@"

