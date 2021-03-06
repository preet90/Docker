## Builds a base image with OS application dependencies ready installed
## For use with OpenEyes.

ARG OS_VERSION=bionic
ARG BUILD_PHP_VERSION="5.6"

FROM ubuntu:$OS_VERSION

ARG OS_VERSION
ARG BUILD_PHP_VERSION
ARG DEBIAN_FRONTEND=noninteractive
ARG TIMEZONE="Europe/London"

ENV TZ=$TIMEZONE

ENV PHP_VERSION=$BUILD_PHP_VERSION

# Set timezone, add common packages, apt clean at the end to minimise layer size
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
 && apt-get update && apt-get install -y --no-install-recommends \
    apache2 \
    bc \
    curl \
    cron \
    debconf-utils \
    gamin \
    ghostscript \
    git-core \
    gnupg \
    jq \
    libgamin0 \
    libjpeg62 \
    libreoffice-common \
    libreoffice-core \
    libreoffice-writer \
    mariadb-client \
    nano \
    ssh \
    unzip \
    xfonts-75dpi \
    xfonts-base \
    sudo \
    wget \
    zip \
  && apt-get autoremove -y \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get clean -y \
  && rm -rf /var/www/html/* \
  && git config --global core.fileMode false

# Add additional PPAs depending on OS
ADD sources.${OS_VERSION}/ sources
ADD set-sources.sh set-sources.sh

RUN bash set-sources.sh \
    && echo ". /etc/profile" >> /root/.bashrc \
    && echo ". /env.sh 2>/dev/null " >> /root/.bashrc

# Install furtherapps, plus npm, using additional PPAs
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libapache2-mod-php${PHP_VERSION} \
    nodejs \
    npm \
    php${PHP_VERSION} \
    php${PHP_VERSION}-cli \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-gd \
    php${PHP_VERSION}-imagick \
    php${PHP_VERSION}-ldap \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-mysql \
    php${PHP_VERSION}-xsl \
    php${PHP_VERSION}-zip \
    ruby-compass \
  && [ $(echo "${PHP_VERSION} < 7.2" | bc -l) = 1 ] && apt-get install -y --no-install-recommends php${PHP_VERSION}-mcrypt || : \
  && npm install -q -g npm \
  && a2enmod rewrite \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/* \
  && rm -rf /tmp/*

# Install wkhtmltopdf
RUN wget -O /wkhtml.deb https://downloads.wkhtmltopdf.org/0.12/0.12.5/wkhtmltox_0.12.5-1.${OS_VERSION}_amd64.deb \
    && dpkg -i --force-depends /wkhtml.deb \
    && rm /wkhtml.deb \
    && rm -rf /tmp/*

# Dependencies for Puppeteer headless chrome browser - only install if PHP ver > 7
RUN [ $(echo "7 <= ${PHP_VERSION}" | bc -l) = 1 ] && { apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    fonts-liberation \
    gconf-service \
    libappindicator1 \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libc6 \
    libcairo2 \
    libcups2 \
    libdbus-1-3 \
    libexpat1 \
    libfontconfig1 \
    libgcc1 \
    libgconf-2-4 \
    libgdk-pixbuf2.0-0 \
    libglib2.0-0 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libstdc++6 \
    libx11-6 \
    libx11-xcb1 \
    libxcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxss1 \
    libxtst6 \
    lsb-release \
    wget \
    xdg-utils \
    && apt-get autoremove -y && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* ; } || :

# SETUP apache config
# Enable add custom PHP and apache settings (including timezone), plus configure SSH
COPY 99-openeyes.ini /etc/php/${PHP_VERSION}/apache2/conf.d/99-openeyes.ini
COPY set_php_vars.sh /set_php_vars.sh
RUN chmod 774 /set_php_vars.sh \ 
  && bash /set_php_vars.sh \
  && echo "date.timezone = ${TZ:-'Europe/London'}" > /etc/php/${PHP_VERSION}/apache2/conf.d/99-timezone.ini \
  && ln -sf /etc/php/${PHP_VERSION}/apache2/conf.d/99-openeyes.ini /etc/php/${PHP_VERSION}/cli/conf.d/99-openeyes.ini \
  && ln -sf /etc/php/${PHP_VERSION}/apache2/conf.d/99-timezone.ini /etc/php/${PHP_VERSION}/cli/conf.d/99-timezone.ini \
  && mkdir -p /var/log/php 2>/dev/null || : \
  && chown www-data /var/log/php \
  && chown www-data /var/log/php \
  && echo "ServerName localhost" >> /etc/apache2/apache2.conf \
  && a2enmod rewrite \
  && echo "AuthorizedKeysFile  /run/.ssh/authorized_keys /.authorized_keys .ssh/authorized_keys %h/.ssh/authorized_keys" >> /etc/ssh/sshd_config

# Install composer
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
  && php composer-setup.php \
  && php -r "unlink('composer-setup.php');" \
  && mv composer.phar /usr/local/bin/composer \
  && rm -rf /tmp/*

EXPOSE 80 3306 22

