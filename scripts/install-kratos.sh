
# Delete previous files
echo "Hi"
CURR_DIR=$PWD
PROBLEMTYPE_DIR_NAME=kratos.gid
mkdir ${PROBLEMTYPE_DIR_NAME}
rm -r /gid/problemtypes/kratos.gid

if [[ -z "${GITHUB_ACTION}" ]]; then
    echo "Download GiDInterface master branch"
    cd /tmp
    git clone https://github.com/KratosMultiphysics/GiDInterface.git
    echo "Downloaded"
    mv -f /tmp/GiDInterface/kratos.gid /gid/problemtypes
    rm -r /tmp/GiDInterface
fi

echo "Download GiDInterface master branch"
cd /tmp
wget --no-check-certificate --cipher 'DEFAULT:!DH' --quiet https://web.cimne.upc.edu/users/fjgarate/descargas/kratos-latest-linux-64.tgz
echo "Downloaded"

echo "Uncompress"
tar -xf ./kratos-latest-linux-64.tgz

if [[ -z "${GITHUB_ACTION}" ]]; then
    mkdir /gid/problemtypes/kratos.gid/exec/Kratos
    mv /tmp/KratosRelease/* /gid/problemtypes/kratos.gid/exec/Kratos
    rm -r /tmp/KratosRelease
fi 
echo "KRATOS READY"