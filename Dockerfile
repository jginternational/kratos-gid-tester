# specify the node base image with your desired version node:<version>
FROM node:alpine

WORKDIR /app
COPY . .
RUN rm "project/kratos x64.tester/config/preferences.xml"
RUN mv "project/kratos x64.tester/config/preferencesdocker.xml" "project/kratos x64.tester/config/preferences.xml"
RUN npm install
RUN apk update && apk add tcl
RUN apk add --no-cache git
RUN "scripts/install-gid.sh"
RUN "scripts/install-kratos.sh"
RUN ls scripts
CMD node "scripts/noderundocker.js"