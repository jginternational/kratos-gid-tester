#!/bin/bash
# Delete previous files
# echo "Hi"
# CURR_DIR=$PWD
# PROBLEMTYPE_DIR_NAME=kratos.gid
# mkdir ${PROBLEMTYPE_DIR_NAME}
rm -r /gid/problemtypes/kratos.gid

if [[ -v "${GITHUB_ACTION}" ]]; then
    echo "You are in Github Actions -> your code will arrive later"
else
    echo "Download GiDInterface master branch"
    cd /tmp
    git clone https://github.com/KratosMultiphysics/GiDInterface.git
    echo "Downloaded"
    cd GiDInterface
    # git checkout write-geoms-migration
    # echo "Branch write-geoms-migration checked out"
    mv -f /tmp/GiDInterface/kratos.gid /gid/problemtypes
    rm -r /tmp/GiDInterface
    # wait 5 seconds
    sleep 5
fi
chmod -R 777 /gid/problemtypes/kratos.gid/exec

# echo "Download kratos bins"
# python3 -m pip install --upgrade --force-reinstall --no-cache-dir KratosMultiphysics-all==10.2.1
# echo "Downloaded"
# sleep 5
echo "KRATOS READY"