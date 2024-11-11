#!/bin/sh

# Try to load host-specific initialization script from bootserver
curl -s $(sed -e 's|.* root=||' -e 's|\(http://[^ ]\+/\).*|\1|' /proc/cmdline)$(hostname).sh | bash
