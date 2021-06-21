FROM gidhome/docker-unix-developer

WORKDIR /app

# First install invariable dependencies
RUN apt-get -y install git
RUN apt-get -y install curl
RUN curl -sL https://deb.nodesource.com/setup_13.x | bash -
RUN apt-get -y install nodejs

# Get the kratos problemtype
COPY ./scripts/install-kratos.sh "scripts/install-kratos.sh"
RUN chmod 750 "scripts/install-kratos.sh"
RUN "scripts/install-kratos.sh"

# js to run
COPY "scripts/runAllCases.js" "scripts/runAllCases.js"
COPY package.json package.json
RUN npm install

# Install Tester
ADD scripts/tester.tar .
#COPY "scripts/tester.tcl" ./tester/tester.tcl
COPY batchs batchs
COPY xmls xmls
COPY project project
RUN mv "project/kratos x64.tester/config/preferencesdocker.xml" "project/kratos x64.tester/config/preferences.xml"

#CMD node "scripts/runAllCases.js"