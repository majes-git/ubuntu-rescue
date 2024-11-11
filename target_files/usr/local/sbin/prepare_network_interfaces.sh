#!/bin/sh

LOCAL_CONFIG=/vpool/local_config
NETWORK_INTERFACES=$LOCAL_CONFIG/network/interfaces

if ls $NETWORK_INTERFACES >/dev/null 2>&1;  then
    # individual network config detected - copy it to /etc
    cp $NETWORK_INTERFACES /etc/network/interfaces
fi
