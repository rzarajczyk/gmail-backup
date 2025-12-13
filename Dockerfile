FROM debian:bookworm-slim

LABEL maintainer="Gmail Backup Container"
LABEL description="Gmail backup with OfflineIMAP, Dovecot and Rainloop"

# Environment variables with defaults
ENV GMAIL_USER=""
ENV GMAIL_APP_PASSWORD=""
ENV RAINLOOP_PASSWORD=""
ENV SYNC_INTERVAL=3600
ENV DOVECOT_USER=vmail
ENV DOVECOT_UID=1000
ENV DOVECOT_GID=1000
ENV RAINLOOP_PORT=8080
ENV DATA_DIR=/data

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    offlineimap \
    dovecot-imapd \
    dovecot-lmtpd \
    dovecot-fts-xapian \
    nginx \
    php-fpm \
    php-curl \
    php-xml \
    php-mbstring \
    php-json \
    php-imap \
    curl \
    ca-certificates \
    supervisor \
    procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create data directories
RUN mkdir -p /data/mail /data/rainloop /data/dovecot /data/offlineimap \
    && mkdir -p /var/log/supervisor \
    && mkdir -p /var/www/rainloop

# Download and install Rainloop
RUN curl -sL https://repository.rainloop.net/installer.php -o /var/www/rainloop/installer.php \
    && cd /var/www/rainloop \
    && php installer.php \
    && rm -f installer.php \
    && chown -R www-data:www-data /var/www/rainloop

# Copy configuration files
COPY config/nginx.conf /etc/nginx/sites-available/default
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY config/sync-mail.sh /usr/local/bin/sync-mail.sh
COPY config/entrypoint.sh /entrypoint.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/sync-mail.sh /entrypoint.sh

# Create vmail user for dovecot
RUN groupadd -g ${DOVECOT_GID} vmail \
    && useradd -u ${DOVECOT_UID} -g vmail -d /data/mail -s /usr/sbin/nologin vmail

# Set permissions
RUN chown -R vmail:vmail /data/mail \
    && chmod -R 700 /data/mail

# Expose ports
EXPOSE 8080 143

# Health check
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1

# Volumes
VOLUME ["/data"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

