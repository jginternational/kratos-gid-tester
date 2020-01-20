
# COPY ./install-kratos.sh "scripts/install-kratos.sh"
# RUN chmod 750 "scripts/install-kratos.sh"
# RUN "scripts/install-kratos.sh"

rm -r /gid/gid-x64/problemtypes/kratos.gid
mkdir /gid/gid-x64/problemtypes/kratos.gid
echo "Download GiDInterface master branch"
git clone https://github.com/KratosMultiphysics/GiDInterface.git
echo "Downloaded"
mv -f /app/GiDInterface/kratos.gid /gid/gid-x64/problemtypes/
rm -r /app/GiDInterface


echo "Download GiDInterface master branch"
TARFILENAME=kratos-7.1-linux-64.tgz
#wget https://github.com/KratosMultiphysics/Kratos/releases/download/7.1/${TARFILENAME}
wget --quiet https://web.cimne.upc.edu/users/fjgarate/descargas/images/${TARFILENAME}
echo "Downloaded"
echo "Uncompress"
tar -xf ${TARFILENAME} 
rm ${TARFILENAME}
mkdir /gid/gid-x64/problemtypes/kratos.gid/exec/Kratos
mv -f /app/KratosRelease/* /gid/gid-x64/problemtypes/kratos.gid/exec/Kratos
rm -r /app/KratosRelease
echo "KRATOS READY"