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

error() {
    echo "Fout: $*" >&2
    exit 1
}

ip_to_int() {
    local ip=$1
    local a b c d

    IFS='.' read -r a b c d <<< "$ip" || return 1

    for octet in "$a" "$b" "$c" "$d"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || return 1
        (( octet >= 0 && octet <= 255 )) || return 1
    done

    echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

int_to_ip() {
    local int=$1
    echo "$(( (int >> 24) & 255 )).$(( (int >> 16) & 255 )).$(( (int >> 8) & 255 )).$(( int & 255 ))"
}

parse_cidr() {
    local cidr=$1
    local network prefix

    IFS='/' read -r network prefix <<< "$cidr" || return 1
    [[ -n "$network" && -n "$prefix" ]] || return 1
    [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
    (( prefix >= 0 && prefix <= 32 )) || return 1

    local network_int
    network_int=$(ip_to_int "$network") || return 1

    echo "$network_int $prefix"
}

contains_ip() {
    local needle=$1
    shift
    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

get_subnet_bounds() {
    local cidr=$1
    local network_int prefix
    read -r network_int prefix <<< "$(parse_cidr "$cidr")" || return 1

    local mask
    if (( prefix == 0 )); then
        mask=0
    else
        mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
    fi

    local subnet_start subnet_end
    subnet_start=$(( network_int & mask ))
    subnet_end=$(( subnet_start | (~mask & 0xFFFFFFFF) ))

    echo "$subnet_start $subnet_end $prefix"
}

validate_ip_in_subnet() {
    local ip=$1
    local subnet_start=$2
    local subnet_end=$3

    local ip_int
    ip_int=$(ip_to_int "$ip") || return 1

    (( ip_int >= subnet_start && ip_int <= subnet_end ))
}

give_ip() {
    [[ -f "$DB_FILE" ]] || error "Bestand '$DB_FILE' bestaat niet"

    mapfile -t lines < "$DB_FILE"
    (( ${#lines[@]} > 0 )) || error "Bestand '$DB_FILE' is leeg"

    local cidr="${lines[0]}"
    local subnet_start subnet_end prefix
    read -r subnet_start subnet_end prefix <<< "$(get_subnet_bounds "$cidr")" || error "Ongeldige subnetregel: $cidr"

    local used_ips=()
    local i line
    for (( i=1; i<${#lines[@]}; i++ )); do
        line="${lines[$i]}"
        [[ -z "$line" ]] && continue
        ip_to_int "$line" >/dev/null 2>&1 || error "Ongeldig IP-adres in $DB_FILE: $line"
        validate_ip_in_subnet "$line" "$subnet_start" "$subnet_end" || error "IP buiten subnet in $DB_FILE: $line"
        used_ips+=("$line")
    done

    local start end candidate
    start=$subnet_start
    end=$subnet_end

    # Bij normale subnetten slaan we network- en broadcast-adres over
    if (( prefix <= 30 )); then
        start=$(( subnet_start + 1 ))
        end=$(( subnet_end - 1 ))
    fi

    (( start <= end )) || error "Geen bruikbare host-adressen in subnet $cidr"

    local current_ip
    for (( candidate=start; candidate<=end; candidate++ )); do
        current_ip=$(int_to_ip "$candidate")
        if ! contains_ip "$current_ip" "${used_ips[@]:-}"; then
            echo "$current_ip"
            exit 0
        fi
    done

    error "Geen vrij IP-adres beschikbaar in subnet $cidr"
}

remove_ip() {
    local target_ip=$1

    [[ -f "$DB_FILE" ]] || error "Bestand '$DB_FILE' bestaat niet"
    ip_to_int "$target_ip" >/dev/null 2>&1 || error "Ongeldig IP-adres: $target_ip"

    mapfile -t lines < "$DB_FILE"
    (( ${#lines[@]} > 0 )) || error "Bestand '$DB_FILE' is leeg"

    local tmp_file
    tmp_file=$(mktemp)

    {
        echo "${lines[0]}"
        local i line removed=0
        for (( i=1; i<${#lines[@]}; i++ )); do
            line="${lines[$i]}"
            if [[ "$line" == "$target_ip" && $removed -eq 0 ]]; then
                removed=1
                continue
            fi
            [[ -n "$line" ]] && echo "$line"
        done

        if (( removed == 0 )); then
            rm -f "$tmp_file"
            error "IP-adres niet gevonden in $DB_FILE: $target_ip"
        fi
    } > "$tmp_file"

    mv "$tmp_file" "$DB_FILE"
    echo "Verwijderd: $target_ip"
}

main() {
    (( $# >= 1 )) || usage

    case "$1" in
        give)
            (( $# == 1 )) || usage
            give_ip
            ;;
        remove)
            (( $# == 2 )) || usage
            remove_ip "$2"
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
