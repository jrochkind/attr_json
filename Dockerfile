FROM ruby:2.6.2

RUN apt-get update -qq \
    && apt-get upgrade -y --no-install-recommends \
      build-essential \
      postgresql-client \
    && apt-get clean autoclean \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt /var/lib/cache /var/lib/log

RUN gem install bundler

RUN mkdir -p /app/
WORKDIR /app/

# Add bundle entry point to handle bundle cache
COPY ./docker-entrypoint.sh /usr/local/bin
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]

CMD ["/app/bin/rspec"]
