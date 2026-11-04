FROM debian:bookworm-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils zip libglu1-mesa && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch 3.47.9 https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}" CI=true
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN flutter config --no-analytics && flutter pub get
COPY lib ./lib
COPY web ./web
RUN flutter build web --release --no-pub --no-tree-shake-icons
FROM node:24-bookworm-slim
WORKDIR /app
COPY --from=build /src/build/web ./public
COPY backend/server.mjs backend/empresa.mjs ./backend/
CMD ["node", "backend/server.mjs"]
