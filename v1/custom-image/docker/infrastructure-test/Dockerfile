ARG ALPINE_VERSION=3.16
ARG PYTHON_VERSION=3.10.6
FROM python:${PYTHON_VERSION}-alpine${ALPINE_VERSION} as builder

RUN apk update --no-cache \
    && apk upgrade --no-cache \
    && apk add --no-cache \
    bind-tools \
    curl \
    git \
    jq \
    nodejs \
    npm \
    openssl \
    zip \
    libzip-tools \
    unzip \
    groff \
    build-base \
    libffi-dev \
    cmake \
    && pip --no-cache-dir install --upgrade pip \
    && rm -rf /var/cache/apk/*

ARG AWS_CLI_VERSION=2.7.29
RUN git clone --single-branch --depth 1 -b ${AWS_CLI_VERSION} https://github.com/aws/aws-cli.git

WORKDIR /aws-cli
RUN sed -i'' 's/PyInstaller.*/PyInstaller==5.2/g' requirements-build.txt \
    && python -m venv venv \
    && . venv/bin/activate \
    && scripts/installers/make-exe \
    && unzip -q dist/awscli-exe.zip \
    && aws/install --bin-dir /usr/local/bin

RUN echo "alpine version: $(cat /etc/alpine-release)" \
    && aws --version \
    && curl --version \
    && git --version \
    && jq -V \
    && echo "npm: $(npm --version)" \
    && echo "node: $(node --version)" \
    && echo python --version \
    && echo "zip $(zip -v)" \ 
    && zipcmp -V