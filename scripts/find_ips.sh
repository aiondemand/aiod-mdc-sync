#!/bin/bash

echo "Network Interface Information:"
echo "-------------------------"

# Show all interfaces with IPs
ip -4 addr show | grep -v 'valid_lft' | grep -v 'scope host' | awk '
    /^[0-9]+:/ { iface=$2 }
    /inet / { 
        split($2, a, "/")
        printf "%-12s %s\n", iface, a[1]
    }'

echo -e "\nPublic IP (if available):"
echo "-------------------------"
curl -s ifconfig.me

echo -e "\nHostname Information:"
echo "-------------------------"
hostname -I