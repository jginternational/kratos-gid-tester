rm -r /gid/gid-x64/problemtypes/kratos.gid
mkdir /gid/gid-x64/problemtypes/kratos.gid
echo "Download"
git clone https://github.com/KratosMultiphysics/GiDInterface.git
echo "Downloaded"
mv -f /app/GiDInterface/kratos.gid/* /gid/gid-x64/problemtypes/kratos.gid
rm -r /app/GiDInterface
ls

TARFILENAME=kratos-7.1-linux-64.tgz
#wget https://github.com/KratosMultiphysics/Kratos/releases/download/7.1/${TARFILENAME}
wget https://web.cimne.upc.edu/users/fjgarate/descargas/images/${TARFILENAME}
tar -xf ${TARFILENAME} 
rm ${TARFILENAME}
mkdir /gid/gid-x64/problemtypes/kratos.gid/exec/Kratos
mv -f /app/KratosRelease/* /gid/gid-x64/problemtypes/kratos.gid/exec/Kratos
rm -r /app/KratosRelease
ls