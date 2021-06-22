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
cd /tmp
wget --no-check-certificate --cipher 'DEFAULT:!DH' --quiet https://web.cimne.upc.edu/users/fjgarate/descargas/kratos-latest-linux-64.tar.gz
echo "Downloaded"

echo "Uncompress"
tar -xf ./kratos-latest-linux-64.tar.gz

if [[ -v "${GITHUB_ACTION}" ]]; then
    echo "You are in Github Actions -> your exe will be placed later"
else 
    mkdir /gid/problemtypes/kratos.gid/exec/Kratos
    mv /tmp/bin/Release/* /gid/problemtypes/kratos.gid/exec/Kratos
    rm -r /tmp/bin/Release
fi 
echo "KRATOS READY"