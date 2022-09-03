ARG ALPINE_VERSION=3.16
ARG PYTHON_VERSION=3.10.6
FROM python:${PYTHON_VERSION}-alpine${ALPINE_VERSION} as builder

RUN apk update \
    && apk upgrade \
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
    && pip install --upgrade pip \
    && rm -rf /var/cache/apk/*

ARG AWS_CLI_VERSION=2.7.29
RUN git clone --single-branch --depth 1 -b ${AWS_CLI_VERSION} https://github.com/aws/aws-cli.git

WORKDIR /aws-cli
RUN sed -i'' 's/PyInstaller.*/PyInstaller==5.2/g' requirements-build.txt
RUN python -m venv venv
RUN . venv/bin/activate
RUN scripts/installers/make-exe
RUN unzip -q dist/awscli-exe.zip
RUN aws/install --bin-dir /aws-cli-bin
RUN /aws-cli-bin/aws --version

# reduce image size: remove autocomplete and examples
RUN rm -rf /usr/local/aws-cli/v2/current/dist/aws_completer /usr/local/aws-cli/v2/current/dist/awscli/data/ac.index /usr/local/aws-cli/v2/current/dist/awscli/examples
RUN find /usr/local/aws-cli/v2/current/dist/awscli/botocore/data -name examples-1.json -delete

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