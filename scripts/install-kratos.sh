#!/bin/bash
# Delete previous files
echo "Hi"
CURR_DIR=$PWD
PROBLEMTYPE_DIR_NAME=kratos.gid
mkdir ${PROBLEMTYPE_DIR_NAME}
rm -r /gid/problemtypes/kratos.gid

if [[ -v "${GITHUB_ACTION}" ]]; then
    echo "You are in Github Actions -> your code will arrive later"
else
    echo "Download GiDInterface master branch"
    cd /tmp
    git clone https://github.com/KratosMultiphysics/GiDInterface.git
    mv -f /tmp/GiDInterface/kratos.gid /gid/problemtypes
    rm -r /tmp/GiDInterface
    echo "Downloaded"
fi

echo "Download kratos bins"
python3 -m pip install --upgrade --force-reinstall --no-cache-dir KratosMultiphysics-all==9.5.2
echo "Downloaded"

echo "KRATOS READY"