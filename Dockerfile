FROM gidhome/docker-unix-developer

WORKDIR /app

# First install invariable dependencies
RUN apt-get -y install git
RUN apt-get -y install curl
RUN curl -sL https://deb.nodesource.com/setup_13.x | bash -
RUN apt-get -y install nodejs
RUN apt-get -y install python3-pip

COPY package.json package.json
RUN npm install

# Install Tester
ADD scripts/tester.tar .
#COPY "scripts/tester.tcl" ./tester/tester.tcl
COPY batchs batchs
COPY xmls xmls
COPY project project
RUN mv "./project/kratos x64.tester/config/preferences_docker.xml" "./project/kratos x64.tester/config/preferences.xml"
RUN find . -type f -name '*.bch'| xargs sed -i 's/\[tester::get_tmp_folder\]/\/tmp/g'

# js to run
COPY "scripts/runAllCases.js" "scripts/runAllCases.js"