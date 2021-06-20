FROM gidhome/docker-unix-developer

WORKDIR /app

RUN apt-get -y install git

COPY ./scripts/install-kratos.sh "scripts/install-kratos.sh"
RUN chmod 750 "scripts/install-kratos.sh"
RUN "scripts/install-kratos.sh"


RUN apt-get -y install curl
RUN curl -sL https://deb.nodesource.com/setup_13.x | bash -
RUN apt-get -y install nodejs

COPY "scripts/runAllCases.js" "scripts/runAllCases.js"
COPY "scripts/tester-linux-64" "scripts/tester-linux-64"
RUN chmod 750 "scripts/tester-linux-64"
COPY batchs batchs
COPY xmls xmls
COPY package.json package.json
COPY project project
RUN mv "project/kratos x64.tester/config/preferencesdocker.xml" "project/kratos x64.tester/config/preferences.xml"

RUN npm install

#COPY "scripts/tester.tcl" "/gid/gid-x64/tester.tcl"
CMD node "scripts/runAllCases.js"