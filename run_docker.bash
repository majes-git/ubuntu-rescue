#!/bin/bash

# Test if sudo is installed, otherwise run docker directly (requires root privileges)
which sudo >/dev/null && docker="sudo docker" || { docker="docker"; if [ "$UID" != "0" ]; then echo "* This script will likely not work without root priviliges!"; fi; }

if [ ! -s authorized_keys ]; then
    echo "* There is no authorized_keys file or it is empty."
    echo "  You will not be able to log into the rescue system using ssh!"
fi

script=create_ubuntu_rescue.bash

environment=""
if [ -n "$http_proxy" ]; then
    environment="-e http_proxy=$http_proxy $environment"
fi

$docker run --privileged --rm -it \
    -v $(pwd)/target:/target \
    -v $(pwd)/target_files:/target_files \
    -v $(pwd)/authorized_keys:/authorized_keys \
    -v $(pwd)/extra_packages:/extra_packages \
    -v $(pwd)/$script:/$script \
       $environment \
    ubuntu /$script > run_docker.log 2>&1

echo ""
echo "Generated files:"
echo "================"
find target/ -type f 
