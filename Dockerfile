
FROM fjgarate/gid-kratos-static-test


WORKDIR /app

COPY "scripts/noderundocker.js" "scripts/noderundocker.js"
COPY "scripts/tester-linux-64" "scripts/tester-linux-64"
RUN chmod 750 "scripts/tester-linux-64"
COPY batchs batchs
COPY xmls xmls
COPY package.json package.json
COPY project project
RUN rm "project/kratos x64.tester/config/preferences.xml"
RUN mv "project/kratos x64.tester/config/preferencesdocker.xml" "project/kratos x64.tester/config/preferences.xml"

RUN npm install
COPY "scripts/tester.tcl" "/gid/gid-x64/tester.tcl"
CMD node "scripts/noderundocker.js"