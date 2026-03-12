#!/bin/bash

# Define the path to configuration and database files.
CONFIG_FILE="ip_manager.conf"
DB_FILE="ip_db"

# Function to initialize the IP address database if it doesn't exist.
init_ip_db() {
  if [ ! -f "$DB_FILE" ]; then
    echo "Initializing IP address database..."
    touch "$DB_FILE"
  fi
}

# Function to get the subnet from the configuration file.
get_subnet() {
  subnet=$(grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$' "$CONFIG_FILE" | cut -d '/' -f 1)
  echo "$subnet"
}

# Function to generate the next available IP address.
get_next_ip() {
  subnet=$(get_subnet)
  used_ips=($(grep -E '^[0-9]{1,3}\.){3}[0-9]{1,3}$' "$DB_FILE"))
  
  # Generate a list of all possible IPs in the subnet.
  ip_range=($(ipcalc $subnet | grep "Network" | cut -d ':' -f 2- | tr ',' '\n'))
  
  for ip in "${ip_range[@]}"; do
    if [[ ! " ${used_ips[*]} " =~ " ${ip} " ]]; then
      echo "$ip"
      return
    fi
  done

  echo "No available IP addresses in the subnet."
}

# Function to handle the 'give' command.
give_ip() {
  next_ip=$(get_next_ip)
  
  if [[ "$next_ip" != *"IP address"* ]]; then
    echo "Giving IP address: $next_ip"
    echo "$next_ip" >> "$DB_FILE"
  fi
}

# Function to handle the 'remove' command.
remove_ip() {
  ip_to_remove=$1

  if grep -q "^$ip_to_remove$" "$DB_FILE"; then
    echo "Removing IP address: $ip_to_remove"
    sed -i "/^$ip_to_remove$/d" "$DB_FILE"
  else
    echo "IP address not found in database."
  fi
}

# Main function to handle script arguments.
main() {
  init_ip_db

  case "$1" in
    give)
      give_ip
      ;;
    remove)
      if [ -n "$2" ]; then
        remove_ip "$2"
      else
        echo "Usage: $0 remove <IP address>"
      fi
      ;;
    *)
      echo "Usage: $0 {give|remove <IP address>}"
      ;;
  esac
}

# Execute the main function with script arguments.
main "$@"

# End of script: src/ip_manager.sh