#!/bin/bash

echo "Network Interface Information:"
echo "-------------------------"

# Show all interfaces with IPs (excluding loopback and docker interfaces)
echo "Local Network IPs:"
ip -4 addr show | grep -v 'valid_lft' | grep -v 'scope host' | grep -v 'docker' | grep -v 'br-' | grep -v 'lo' | awk '
    /^[0-9]+:/ { iface=$2 }
    /inet / { 
        split($2, a, "/")
        printf "%-12s %s\n", iface, a[1]
    }'

echo -e "\nPrimary Network IP:"
echo "-------------------------"
# Get the primary network interface IP (usually eth0 or ens*)
primary_ip=$(ip -4 addr show | grep -v 'docker' | grep -v 'br-' | grep -v 'lo' | grep 'inet' | grep -E 'eth0|ens' | head -1 | awk '{print $2}' | cut -d/ -f1)
echo "$primary_ip"

echo -e "\nRecommended IP to use:"
echo "-------------------------"
if [ -n "$primary_ip" ]; then
    echo "Use this IP in your .env file: $primary_ip"
else
    echo "Could not determine primary IP. Please check network configuration."
fi

# Test local network connectivity
echo -e "\nNetwork Connectivity Test:"
echo "-------------------------"
echo "Testing connectivity to common local network ranges..."
for subnet in "192.168" "10.0" "172.16"; do
    echo "Scanning $subnet.* network..."
    for i in {1..254}; do
        timeout 0.1 ping -c 1 "$subnet.1.$i" >/dev/null 2>&1 && echo "Found host: $subnet.1.$i"
    done
done

