FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml ./
RUN dart pub get
COPY . ./
RUN dart compile exe bin/server.dart -o /app/cernogram-gateway

FROM debian:bookworm-slim
RUN useradd --system --uid 10001 --create-home cernogram \
    && mkdir -p /data \
    && chown -R cernogram:cernogram /data
COPY --from=build /app/cernogram-gateway /usr/local/bin/cernogram-gateway
USER cernogram
ENV CG_HOST=0.0.0.0 \
    CG_PORT=8080 \
    CG_DATA_DIR=/data
VOLUME ["/data"]
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/cernogram-gateway"]
