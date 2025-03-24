# nginx-acme.sh
This project provides a Dockerized Nginx container that automatically manages SSL/TLS certificates using acme.sh. It monitors your Nginx configuration files for domain definitions and automatically issues, renews, and installs certificates with minimal downtime.

# Usage

- Pull container:
    ```bash
    podman pull ghcr.io/grisha765/nginx-acme.sh:latest
    ```

- Place your domain-specific Nginx configuration files in the mounted directory `/etc/nginx/conf.d`:
    - Create directory for configuration files:
        ```bash
        mkdir /path/to/nginx.conf
        ```
    - Each file should be named as domain.conf (e.g., example.com.conf):
        ```nginx
        # /path/to/nginx.conf/example.com.conf
        server {
            listen 443 ssl;
            server_name example.com;

            ssl_certificate /etc/nginx/ssl/example.com/cert.pem;
            ssl_certificate_key /etc/nginx/ssl/example.com/key.pem;

            ssl_protocols TLSv1.2 TLSv1.3;
            ssl_prefer_server_ciphers on;
            ssl_ciphers HIGH:!aNULL:!MD5;

            location / {
                return 404;
            }
        }
        ```

- Run container:
    ```bash
    podman run -d \
    --name nginx-acme.sh \
    --network=host \
    -e SLEEP_INTERVAL=20 \
    -e CA_SERVER=letsencrypt \
    -v /path/to/nginx.conf:/etc/nginx/conf.d \
    -v acme.sh-config:/acme.sh \
    localhost/nginx-acmesh:latest
    ```

# Features

- Dockerized Nginx: Runs on the official Nginx image.
- Automated Certificate Management: Uses acme.sh to issue, renew, and install certificates.
- ALPN Challenge Support: Leverages the ALPN protocol for domain validation.
- Config-Driven Domain Setup: Reads domain names from your Nginx configuration files located in /etc/nginx/conf.d/.
