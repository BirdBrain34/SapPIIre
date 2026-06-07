# Stage 1: Build the Flutter Web application
FROM debian:bookworm-slim AS build-env

RUN apt-get update && apt-get install -y \
    curl git unzip xz-utils zip libglu1-mesa && \
    rm -rf /var/lib/apt/lists/*

# Bumped to 3.44.1 to satisfy Dart SDK ^3.10.8 requirement
RUN git clone https://github.com/flutter/flutter.git /usr/local/flutter \
    --branch 3.44.1 --depth 1

ENV PATH="/usr/local/flutter/bin:${PATH}"
ENV PATH="/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

RUN flutter doctor
RUN flutter config --no-analytics

WORKDIR /app
COPY . .

RUN flutter build web --release

# Stage 2: Serve via Nginx with Railway's dynamic $PORT
FROM nginx:alpine

COPY --from=build-env /app/build/web /usr/share/nginx/html

CMD ["/bin/sh", "-c", \
    "sed -i 's/listen 80/listen '\"$PORT\"'/g' /etc/nginx/conf.d/default.conf && \
     nginx -g 'daemon off;'"]