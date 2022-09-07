FROM docker:dind

RUN apk update \
    && apk upgrade \
    && apk add --no-cache \
    coreutils \
    curl \
    docker-compose \
    git \
    jq \
    nodejs \
    npm \
    zip \
    libzip-tools \
    python3 \
    python3-dev \
    py3-pip \
    build-base \
    groff \
    libffi-dev \
    cmake \
    && pip install --upgrade pip \
    && rm -rf /var/cache/apk/*

ARG AWS_CLI_VERSION=2.7.29
RUN git clone --single-branch --depth 1 -b ${AWS_CLI_VERSION} https://github.com/aws/aws-cli.git

WORKDIR /aws-cli
RUN sed -i'' 's/PyInstaller.*/PyInstaller==5.2/g' requirements-build.txt
RUN ln -s /usr/bin/python3 /usr/bin/python
RUN python -m venv venv
RUN . venv/bin/activate
RUN scripts/installers/make-exe
RUN unzip -q dist/awscli-exe.zip
RUN aws/install --bin-dir /aws-cli-bin

RUN echo "alpine version: $(cat /etc/alpine-release)" \
    && aws --version \
    && curl --version \
    && docker -v \
    && docker-compose --version \
    && git --version \
    && jq -V \
    && echo "npm: $(npm --version)" \
    && echo "node: $(node --version)" \
    && echo python --version \
    && zip -v \
    && zipcmp -V