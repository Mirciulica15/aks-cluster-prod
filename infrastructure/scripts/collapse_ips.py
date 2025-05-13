#!/usr/bin/env python3
"""Collapse IPs into minimal supernets under a rule limit.

Script reads JSON from stdin with a key "ips_json" containing a JSON-encoded list of CIDR strings.
It computes the coarsest prefix length l such that the number of distinct /l prefixes covering
all input networks is ≤ MAX_RULES. It then emits those prefixes back as JSON.
"""

import sys
import json
from ipaddress import ip_network, IPv4Network

# Maximum number of rules allowed
MAX_RULES = 950


def find_cover_prefixes(networks, max_rules):
    """
    Find the largest prefix length l where the set of distinct /l networks covering all
    input networks has size <= max_rules.
    Returns that set of IPv4Network objects.
    """
    # Iterate from finest to coarsest (32 down to 0)
    for l in range(32, -1, -1):
        prefixes = set()
        # build mask for prefix l
        if l == 0:
            mask = 0
        else:
            mask = (~((1 << (32 - l)) - 1)) & 0xFFFFFFFF
        for net in networks:
            # mask the network_address to l bits
            addr_int = int(net.network_address) & mask
            prefixes.add(IPv4Network((addr_int, l)))
        if len(prefixes) <= max_rules:
            return prefixes
    # Fallback: only a single /0
    return {IPv4Network('0.0.0.0/0')}


def main():
    """Main function to read input, process IPs, and output results."""
    # Read Terraform's stdin JSON
    data = json.load(sys.stdin)
    # Decode the JSON-encoded IP list
    ips_list = json.loads(data.get('ips_json', '[]'))

    # Parse into IPv4Network objects
    networks = [ip_network(ip) for ip in ips_list]

    # Compute cover prefixes
    cover_nets = find_cover_prefixes(networks, MAX_RULES)

    # Sort by address then prefix length
    sorted_nets = sorted(
        cover_nets,
        key=lambda n: (int(n.network_address), n.prefixlen)
    )

    # Prepare output as JSON-encoded string
    output_ips = [str(n) for n in sorted_nets]
    print(json.dumps({
        'collapsed_ips_json': json.dumps(output_ips)
    }))


if __name__ == '__main__':
    main()
