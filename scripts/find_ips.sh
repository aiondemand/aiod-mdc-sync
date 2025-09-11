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
# Get the primary network interface IP by finding the interface for the default route
primary_ip=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
if [ -z "$primary_ip" ]; then
    # Fallback for systems where the above command doesn't work
    primary_ip=$(ip -4 addr show | grep -v 'docker' | grep -v 'br-' | grep -v 'lo' | grep 'inet' | grep -E 'eth0|ens' | head -1 | awk '{print $2}' | cut -d/ -f1)
fi
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
# Get the subnet from the primary IP
if [ -n "$primary_ip" ]; then
    subnet=$(echo "$primary_ip" | cut -d. -f1-3)
    gateway="${subnet}.1"
    echo "Testing connectivity to gateway ($gateway)..."
    if ping -c 1 -W 1 "$gateway" >/dev/null 2>&1; then
        echo "✅ Network gateway is reachable"
    else
        echo "⚠️  Could not reach network gateway"
    fi
    
    # Test a few nearby IPs (quick check)
    echo "Testing nearby hosts..."
    for i in {2..5}; do
        local_host="${subnet}.$i"
        timeout 0.1 ping -c 1 "$local_host" >/dev/null 2>&1 && echo "Found host: $local_host"
    done
fi

