FROM php:8.5.11-cli@sha256:19642e172d3a542225225e202ddc2c11f67bdcbddf147b676c49338609b9290f

ARG COMPOSER_VERSION=2.10.3
ARG COMPOSER_SHA256=7a2d379d5b8ffdaa028580ef26494c36d2feef4b178d3dd1473a4dbc5e17c8d6

RUN apt-get update \
    && apt-get install --no-install-recommends -y unzip \
    && rm -rf /var/lib/apt/lists/*

RUN php -r "copy('https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar', '/usr/local/bin/composer');" \
    && echo "${COMPOSER_SHA256}  /usr/local/bin/composer" | sha256sum --check --status \
    && chmod 0755 /usr/local/bin/composer \
    && composer --version --no-ansi

WORKDIR /workspace
