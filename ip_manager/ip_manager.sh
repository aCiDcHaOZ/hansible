#!/usr/bin/env bash

# Dit script leest een subnet op basis van de eerste regel van het bestand "ip_db" zoals 10.24.43.0/24. 
# de regels die daarna volgen in het bestand zijn ip-adressen die al in gebruik zijn. 
# Als het script gestart wordt met het argument "give", moet het script een IP-adres teruggeven 
# die nog niet in de lijst staat maar wel binnen het subnet valt. 
# Als het script gestart wordt met het argument "remove <IP-adres>", moet het script de regel 
# verwijderen uit het bestand.

set -euo pipefail

DB_FILE="ip_db"

usage() {
    echo "Gebruik:"
    echo "  $0 give"
    echo "  $0 remove <IP-adres>"
    exit 1
}

ip_to_int() {
    IFS=. read -r a b c d <<< "$1"
    echo $(( (a<<24) + (b<<16) + (c<<8) + d ))
}

int_to_ip() {
    local ip=$1
    echo "$(( (ip>>24)&255 )).$(( (ip>>16)&255 )).$(( (ip>>8)&255 )).$(( ip&255 ))"
}

get_subnet_bounds() {
    local cidr=$1
    IFS=/ read -r net prefix <<< "$cidr"

    local net_int
    net_int=$(ip_to_int "$net")

    local mask=$(( 0xFFFFFFFF << (32-prefix) & 0xFFFFFFFF ))
    local start=$(( net_int & mask ))
    local end=$(( start | (~mask & 0xFFFFFFFF) ))

    echo "$start $end $prefix"
}

ip_used() {
    local ip=$1
    grep -qx "$ip" "$DB_FILE" && return 0 || return 1
}

give_ip() {
    mapfile -t lines < "$DB_FILE"
    cidr="${lines[0]}"

    read -r start end prefix <<< "$(get_subnet_bounds "$cidr")"

    # skip network/broadcast
    if (( prefix <= 30 )); then
        start=$((start+1))
        end=$((end-1))
    fi

    for ((i=start;i<=end;i++)); do
        ip=$(int_to_ip "$i")
        if ! ip_used "$ip"; then
            echo "$ip" >> "$DB_FILE"
            echo "$ip"
            exit 0
        fi
    done

    echo "Geen vrije IP-adressen beschikbaar" >&2
    exit 1
}

remove_ip() {
    ip=$1
    tmp=$(mktemp)

    head -n1 "$DB_FILE" > "$tmp"
    tail -n +2 "$DB_FILE" | grep -vx "$ip" >> "$tmp"

    mv "$tmp" "$DB_FILE"
}

[[ $# -ge 1 ]] || usage

case "$1" in
    give)
        give_ip
        ;;
    remove)
        [[ $# -eq 2 ]] || usage
        remove_ip "$2"
        ;;
    *)
        usage
        ;;
esac