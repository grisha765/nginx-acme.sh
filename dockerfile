FROM docker.io/nginx:latest

WORKDIR /root

RUN curl https://get.acme.sh | sh -s -- force

RUN ln -s /root/.acme.sh/acme.sh /usr/local/bin/acme.sh

VOLUME /etc/nginx/ssl

VOLUME /acme.sh

COPY start.sh /usr/local/bin/start.sh

RUN chmod +x /usr/local/bin/start.sh

CMD ["/usr/local/bin/start.sh"]

