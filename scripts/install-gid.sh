mkdir /gid
cd /gid
# wget https://web.cimne.upc.edu/users/miguel/data/gid/gid14.0.2-linux-x64.tar.gz
# tar -zxvf gid14.0.2-linux-x64.tar.gz
# rm gid14.0.2-linux-x64.tar.gz
# cd gid14.0.2-x64
VERSION=14.1.8d
TARFILENAME=gid${VERSION}-linux-x64.tar.xz
# wget --progress=dot:mega https://www.gidhome.com/archive/GiD_Developer_Versions/Linux/amd64/${TARFILENAME}
wget https://web.cimne.upc.edu/users/fjgarate/descargas/images/${TARFILENAME}
#wget https://www.gidhome.com/archive/GiD_Developer_Versions/Linux/amd64/${TARFILENAME}
# wget --progress=dot:mega https://web.cimne.upc.edu/users/miguel/data/gid/${TARFILENAME}
tar -Jxf ${TARFILENAME}
rm ${TARFILENAME}
# rename folder to a 'common' name known by surpervisord.conf
mv gid${VERSION}-x64 gid-x64
cd gid-x64
echo 147.83.143.50 >> scripts/TemporalVariables
# with 'SoftwareOpenGL 0' snapshots are black
# official version preferences file:
# PREFERENCESFILE=$HOME/.gidDefaults
# developer version preferences file
PREFERENCESFOLDER=$HOME/.gid/${VERSION}/
mkdir -p ${PREFERENCESFOLDER}
PREFERENCESFILE=${PREFERENCESFOLDER}gid.ini
echo "SoftwareOpenGL 1" >> ${PREFERENCESFILE}
echo "Theme_configured 1" >> ${PREFERENCESFILE}
echo "Theme(Current) GiD_classic_renewed" >> ${PREFERENCESFILE}
echo "Theme(MenuType) native" >> ${PREFERENCESFILE}
echo "Theme(HighResolutionScaleFactor) 1" >> ${PREFERENCESFILE}
echo "OGL_configured 1" >> ${PREFERENCESFILE}
echo "Theme_configured 1" >> ${PREFERENCESFILE}
# This is to avoid black screen when doing zoom:
echo "OGL_emulateFrontBuffer 1" >> ${PREFERENCESFILE}
echo "ShowCheckNewVersion 0" >> ${PREFERENCESFILE}
# So that gid opens +0- maximized:
echo "MainWindowGeom 1276x749+0+0" >> ${PREFERENCESFILE}
echo "PrePostStdBarWindowGeom INSIDETOP {} 1 StdBitmaps" >> ${PREFERENCESFILE}
echo "PrePostBitmapsWindowGeom INSIDELEFT {} 1 CreateBitmaps" >> ${PREFERENCESFILE}
echo "PrePostMacrosToolbarWindowGeom INSIDELEFT {} 1 toolbarmacros::Create INSIDELEFT" >> ${PREFERENCESFILE}
echo "PostViewResultsBarWindowGeom INSIDELEFT {} 1 ViewResultsBarBitmaps" >> ${PREFERENCESFILE}
echo "PrePostStatusWindowGeom INSIDE {} 1 BottomStatusFrame" >> ${PREFERENCESFILE}
echo "PrePostTopMenuWindowGeom INSIDE {} 1 TopMenuFrame" >> ${PREFERENCESFILE}
echo "PrePostRightButWindowGeom INSIDE {} RightButtons" >> ${PREFERENCESFILE}
echo "PrePostEntryWindowGeom INSIDE {} 1 BottomEntryFrame" >> ${PREFERENCESFILE}
# ./gid