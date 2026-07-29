FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml ./
RUN dart pub get
COPY bin ./bin
RUN dart compile exe bin/server.dart -o /app/realtime-gateway

FROM debian:bookworm-slim
RUN useradd --system --uid 10001 --create-home cernogram \
    && mkdir -p /var/lib/cernogram \
    && chown -R cernogram:cernogram /var/lib/cernogram
COPY --from=build /app/realtime-gateway /usr/local/bin/realtime-gateway
USER cernogram
ENV CG_BIND=0.0.0.0 \
    CG_PORT=8080 \
    CG_DATA_DIR=/var/lib/cernogram
VOLUME ["/var/lib/cernogram"]
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/realtime-gateway"]
