FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CG_MUSIC_DATA_DIR=/var/lib/cernogram/music

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
       curl \
       ffmpeg \
       libchromaprint-tools \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py ./

RUN useradd --system --uid 10002 --create-home cernogram \
    && mkdir -p /var/lib/cernogram/music \
    && chown -R cernogram:cernogram /var/lib/cernogram

USER cernogram
VOLUME ["/var/lib/cernogram/music"]
EXPOSE 8090

HEALTHCHECK --interval=15s --timeout=3s --start-period=15s --retries=5 \
  CMD curl -fsS http://127.0.0.1:8090/healthz || exit 1

CMD ["uvicorn", "app:APP", "--host", "0.0.0.0", "--port", "8090", "--workers", "1"]
