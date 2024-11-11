#!/bin/sh

NET_IF=$(ip addr ls | sed -n '/inet .* scope global/s/.* global //p')

cat > /etc/network/interfaces.d/$NET_IF <<EOF
auto $NET_IF
iface $NET_IF inet dhcp
EOF
