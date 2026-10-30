FROM gis-base

RUN apt-get update && apt-get install -y --no-install-recommends \
        apache2 \
        libapache2-mod-php \
        php-pgsql \
        openssl \
    && rm -rf /var/lib/apt/lists/*

RUN a2enmod ssl rewrite \
    && a2dissite 000-default \
    && mkdir -p /etc/ssl/gis \
    && openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout /etc/ssl/gis/web.key -out /etc/ssl/gis/web.crt \
        -subj "/C=RU/O=GIS AUO stand/CN=198.51.100.1"

COPY apache/gis-site.conf /etc/apache2/sites-available/gis-site.conf
RUN a2ensite gis-site

COPY site/ /var/www/site/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && chown -R www-data:www-data /var/www/site

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
