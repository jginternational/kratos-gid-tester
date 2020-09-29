
# Delete previous files
echo "Hi"
CURR_DIR=$PWD
PROBLEMTYPE_DIR_NAME=kratos.gid
mkdir ${PROBLEMTYPE_DIR_NAME}
rm -r /gid/problemtypes/kratos.gid

echo "Download GiDInterface master branch"
cd /tmp
git clone https://github.com/KratosMultiphysics/GiDInterface.git
echo "Downloaded"
cd ${CURR_DIR}
mv -f /tmp/GiDInterface/kratos.gid ${CURR_DIR}
rm -r /tmp/GiDInterface

echo "Download GiDInterface master branch"
cd /tmp
#TARFILENAME=kratos-7.1-linux-64.tgz
#wget --quiet https://github.com/KratosMultiphysics/Kratos/releases/download/7.1/${TARFILENAME}
#wget --quiet https://web.cimne.upc.edu/users/fjgarate/descargas/images/${TARFILENAME}
echo "Downloaded"

echo "Uncompress"
tar -xf ./latest-linux-x64.tgz
#tar -xf ${TARFILENAME}
#rm ${TARFILENAME}

mkdir ${CURR_DIR}/${PROBLEMTYPE_DIR_NAME}/exec/Kratos
mv /tmp/zip/dist/runkratos/* ${CURR_DIR}/${PROBLEMTYPE_DIR_NAME}/exec/Kratos
rm -r /tmp/zip

ln -s ${CURR_DIR}/${PROBLEMTYPE_DIR_NAME} /gid/problemtypes/kratos.gid
echo "KRATOS READY"