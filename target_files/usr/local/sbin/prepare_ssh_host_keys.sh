#!/bin/sh

LOCAL_CONFIG=/vpool/local_config

if ls /etc/ssh/ssh_host_*key* >/dev/null 2>&1; then
    # ssh host keys detected - stop here
    exit 0
fi

if ls $LOCAL_CONFIG/ssh/ssh_host_*key* >/dev/null 2>&1;  then
    # persistent ssh host keys detected - let's use them
    for host_key in $LOCAL_CONFIG/ssh/ssh_host_*key*; do
        ln -s $host_key /etc/ssh/
    done
else
    # no persistent ssh host keys - generate temporary keys
    dpkg-reconfigure openssh-server
fi
