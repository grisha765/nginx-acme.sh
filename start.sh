#!/bin/bash

: "${SLEEP_INTERVAL:=20}"

ACME_CMD="/usr/local/bin/acme.sh --config-home /acme.sh"

$ACME_CMD --set-default-ca --server letsencrypt

while true
do
    conf_files=(/etc/nginx/conf.d/*.conf)

    if [ ! -e "${conf_files[0]}" ]; then
        echo "[Error] No .conf files found in /etc/nginx/conf.d/"
        exit 1
    fi
    if [ ${#conf_files[@]} -eq 1 ] && [ "$(basename "${conf_files[0]}")" = "default.conf" ]; then
        echo "[Error] Only default.conf found in /etc/nginx/conf.d/"
        exit 1
    fi

    domains=()
    for f in "${conf_files[@]}"; do
        [ -e "$f" ] || continue
        domain="$(basename "$f" .conf)"
        if [ "$domain" = "default" ]; then
            continue
        fi
        domains+=("$domain")
    done

    needs_renewal=0
    domains_to_renew=()

    needs_install=0
    domains_to_install=()

    for domain in "${domains[@]}"; do
        echo "Checking if certificate needs renewal for domain: $domain"
        check_output=$(
          $ACME_CMD --issue --alpn \
            -d "$domain" 2>&1
        )
        echo "$check_output"
        if ! echo "$check_output" | grep -q "Skipping."; then
            echo "[Info] Certificate for $domain needs renewal."
            domains_to_renew+=("$domain")
            needs_renewal=1
        else
            echo "[Info] Certificate for $domain does not need renewal."
        fi

        echo "Checking if certificate needs install for domain: $domain"
        if [ ! -d "/etc/nginx/ssl/${domain}" ]; then
            echo "[Info] Certificate for $domain needs install."
            domains_to_install+=("$domain")
            needs_install=1
        else
            echo "[Info] Certificate for $domain does not need install."
        fi
    done

    if [ $needs_renewal -eq 1 ]; then
        echo "[Info] Some certificates need renewal. Stopping Nginx..."
        nginx -s stop || true
        for domain in "${domains_to_renew[@]}"; do
            echo "[Info] Issuing/renewing certificate for: $domain"
            rm -rf "/etc/nginx/ssl/${domain}"
            mkdir -p "/etc/nginx/ssl/${domain}"
            $ACME_CMD --issue --alpn \
              -d "$domain" \
              --key-file "/etc/nginx/ssl/${domain}/key.pem" \
              --fullchain-file "/etc/nginx/ssl/${domain}/cert.pem"
        done
        echo "[Info] Starting Nginx..."
        nginx
    else
        echo "[Info] No certificates need renewal. Not restarting Nginx."
    fi

    if [ $needs_install -eq 1 ]; then
        echo "[Info] Some certificates need install. Stopping Nginx..."
        nginx -s stop || true
        for domain in "${domains_to_install[@]}"; do
            echo "[Info] Installing certificate for: $domain"
            mkdir -p "/etc/nginx/ssl/${domain}"
            $ACME_CMD --install-cert \
              -d "$domain" \
              --key-file "/etc/nginx/ssl/${domain}/key.pem" \
              --fullchain-file "/etc/nginx/ssl/${domain}/cert.pem"
        done
        echo "[Info] Starting Nginx..."
        nginx
    else
        echo "[Info] No certificates need install. Not restarting Nginx."
    fi

    echo "[Info] Sleeping $SLEEP_INTERVAL..."
    sleep "$SLEEP_INTERVAL"
done

