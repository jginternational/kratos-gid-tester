FROM gidhome/docker-unix-developer:17.2.0-IR

WORKDIR /app

# Invariable dependencies: git, Node.js 20
RUN apt-get update -y \
 && apt-get install -y git curl ca-certificates gnupg \
 && mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
 && apt-get update -y \
 && apt-get install -y nodejs \
 && rm -rf /var/lib/apt/lists/*

# Kratos in GiD's python (keep in sync with kratos.gid/kratos.xml)
ARG KRATOS_VERSION=10.4.3
RUN /gid/pip install --upgrade --force-reinstall --no-cache-dir "KratosMultiphysics[all]==${KRATOS_VERSION}"

COPY package.json package.json
RUN npm install

# Default problemtype: GiDInterface master. Override it at run time by mounting
# a checkout at /src/kratos.gid (see scripts/docker-entrypoint.sh), or, in CI,
# by moving the checked-out kratos.gid to /gid/problemtypes.
COPY scripts/install-kratos.sh /tmp/install-kratos.sh
RUN chmod +x /tmp/install-kratos.sh && /tmp/install-kratos.sh

# Tester
COPY scripts scripts
COPY batchs batchs
COPY xmls xmls
COPY project project
RUN mv "project/kratos x64.tester/config/preferences_docker.xml" "project/kratos x64.tester/config/preferences.xml" \
 && sed -i 's/\r$//' scripts/*.sh scripts/dockerlauncher.bat \
 && chmod +x scripts/*.sh \
 && mkdir -p /app/output

# add licence
RUN echo "147.83.143.50" > /gid/scripts/TemporalVariables

ENTRYPOINT ["/app/scripts/docker-entrypoint.sh"]
# docker build -t kratos-tester .
# docker run --rm -v <GiDInterface>/kratos.gid:/src/kratos.gid:ro -v ./output:/app/output -e CASES=<names> kratos-tester
