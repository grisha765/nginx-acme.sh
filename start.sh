#!/bin/bash

: "${SLEEP_INTERVAL:=20}"

: "${CA_SERVER:=letsencrypt}"

ACME_CMD="/usr/local/bin/acme.sh --config-home /acme.sh"

$ACME_CMD --set-default-ca --server "$CA_SERVER"

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
        if grep -q "443" "$f" && \
           grep -q "ssl_certificate" "$f" && \
           grep -q "ssl_certificate_key" "$f"; then
            domains+=("$domain")
        fi
    done

    domains_to_issue=()
    domains_to_renew=()
    domains_to_install=()

    current_time=$(date +%s)

    for domain in "${domains[@]}"; do
        echo "=============================="
        echo "Checking status of $domain ..."
        echo "------------------------------"

        info_output=$($ACME_CMD --info -d "$domain" 2>&1 || true)

        if echo "$info_output" | grep -q "No such file or directory"; then
            echo "[Info] $domain: No existing certificate found. Will issue a new one."
            domains_to_issue+=("$domain")
        else
            next_renew_time=$(echo "$info_output" | grep "Le_NextRenewTime=" | cut -d= -f2)
            if [ -z "$next_renew_time" ]; then
                echo "[Warning] $domain: Found existing cert info but no 'Le_NextRenewTime'? Will renew."
                domains_to_renew+=("$domain")
            else
                echo "[Info] $domain: Next renewal time = $next_renew_time"
                if [ "$current_time" -ge "$next_renew_time" ]; then
                    echo "[Info] $domain: Certificate is due (or past due). Will renew."
                    domains_to_renew+=("$domain")
                else
                    echo "[Info] $domain: Certificate is still valid, no immediate renewal needed."
                fi
            fi
        fi

        ssl_dir="/etc/nginx/ssl/${domain}"
        if [ ! -d "$ssl_dir" ]; then
            echo "[Info] $domain: /etc/nginx/ssl/$domain folder not found → must install cert files here."
            domains_to_install+=("$domain")
        else
            echo "[Info] $domain: Certificate directory already exists."
        fi
    done

    if [ ${#domains_to_issue[@]} -gt 0 ] || [ ${#domains_to_renew[@]} -gt 0 ] || [ ${#domains_to_install[@]} -gt 0 ]; then
        echo "[Info] Changes required (issue/renew/install). Stopping Nginx..."
        pidof nginx >/dev/null 2>&1 && nginx -s stop || true
    else
        echo "[Info] No changes required. Not restarting Nginx."
    fi

    for domain in "${domains_to_issue[@]}"; do
        echo "[Info] *** Issuing a new certificate for domain: $domain ***"
        rm -rf "/etc/nginx/ssl/${domain}"
        mkdir -p "/etc/nginx/ssl/${domain}"
        $ACME_CMD --issue --alpn \
          -d "$domain" \
          --key-file "/etc/nginx/ssl/${domain}/key.pem" \
          --fullchain-file "/etc/nginx/ssl/${domain}/cert.pem"
    done

    for domain in "${domains_to_renew[@]}"; do
        echo "[Info] *** Renewing certificate for domain: $domain ***"
        rm -rf "/etc/nginx/ssl/${domain}"
        mkdir -p "/etc/nginx/ssl/${domain}"
        $ACME_CMD --renew --alpn \
          -d "$domain" \
          --key-file "/etc/nginx/ssl/${domain}/key.pem" \
          --fullchain-file "/etc/nginx/ssl/${domain}/cert.pem"
    done

    for domain in "${domains_to_install[@]}"; do
        echo "[Info] *** Installing certificate for domain: $domain ***"
        mkdir -p "/etc/nginx/ssl/${domain}"
        $ACME_CMD --install-cert \
          -d "$domain" \
          --key-file "/etc/nginx/ssl/${domain}/key.pem" \
          --fullchain-file "/etc/nginx/ssl/${domain}/cert.pem"
    done

    if [ ${#domains_to_issue[@]} -gt 0 ] || [ ${#domains_to_renew[@]} -gt 0 ] || [ ${#domains_to_install[@]} -gt 0 ]; then
        echo "[Info] Starting Nginx..."
        nginx
    fi

    echo "[Info] Sleeping $SLEEP_INTERVAL..."
    sleep "$SLEEP_INTERVAL"
done

