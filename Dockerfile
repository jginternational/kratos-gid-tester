FROM gidhome/docker-unix-developer:17.1.5d

WORKDIR /app

# First install invariable dependencies
RUN apt-get -y install git
RUN apt-get -y install curl
RUN apt-get update -y
RUN apt-get install -y ca-certificates curl gnupg
RUN mkdir -p /etc/apt/keyrings
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
RUN echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
RUN apt-get update
RUN apt-get install -y nodejs
RUN apt-get -y install python3-pip python3-venv

COPY package.json package.json
RUN npm install

WORKDIR /tmp
# Install Kratos
ADD scripts/install-kratos.sh .
RUN chmod +x install-kratos.sh
RUN ./install-kratos.sh

WORKDIR /
RUN python3 -m venv kratos-env
# RUN /kratos-env/bin/python3 -m pip install --upgrade --force-reinstall --no-cache-dir KratosMultiphysics-all==10.3.0

# RUN python3 -m pip install --upgrade --force-reinstall --no-cache-dir KratosMultiphysics-all==10.2.1

# Install Tester
WORKDIR /app
# ADD scripts/tester.tar .
COPY scripts/tester.tcl ./tester/tester.tcl
COPY scripts/xunit_log.tcl ./tester/xunit_log.tcl
COPY scripts/run_tests.sh run_tests.sh
COPY batchs batchs
COPY xmls xmls
COPY project project
RUN mv "project/kratos x64.tester/config/preferences_docker.xml" "./project/kratos x64.tester/config/preferences.xml"
# RUN find . -type f -name '*.bch'| xargs sed -i 's/\[tester::get_tmp_folder\]/\/tmp/g'
COPY scripts/KratosVars.txt /gid/scripts/KratosVars.txt

# js to run
COPY "scripts/runAllCases.js" "scripts/runAllCases.js"

# execute the script
CMD ["node", "scripts/runAllCases.js"]
# docker build -t kratos-tester:latest .
# docker run -it --rm  kratos-tester:latest bash