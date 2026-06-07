# Stage 1: Build the Flutter Web application
FROM debian:bookworm-slim AS build-env

# Install fundamental system dependencies
RUN apt-get update && apt-get install -y curl git unzip xz-utils zip libglu1-mesa

# Download and configure the stable Flutter SDK
RUN git clone https://github.com/flutter/flutter.git /usr/local/flutter

# Explicitly set the path environment variables individually
ENV PATH="/usr/local/flutter/bin:${PATH}"
ENV PATH="/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Run doctor to download production artifacts
RUN flutter doctor

# Copy your local repository workspace files into the builder container
WORKDIR /app
COPY . .

# Allow Flutter to run smoothly as root inside the Docker environment
RUN flutter config --no-analytics

# Run the web compilation with perfectly formatted flags
RUN flutter build web --web-renderer=html --release

# Stage 2: Serve the compiled static web files via Nginx
FROM nginx:alpine
COPY --from=build-env /app/build/web /usr/share/nginx/html

# Expose standard web traffic port (Railway will bind to this automatically)
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]