FROM node:16-alpine

#Copying the NodeJS dependency file.
COPY package.json /package.json

#Checking the NodeJS version and then installing the needed modules.
RUN node --version \
    && npm install

#Copying any needed NodeJS apps.
COPY src/app.js /src/app.js

#Copying the GitHub information file.
COPY github.json /github.json

#Run the NodeJS app.
CMD ["node","/src/app.js"]
