FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py ./

RUN useradd --system --uid 10003 --create-home cernogram
USER cernogram
EXPOSE 8082
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=5 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8082/healthz', timeout=2)" || exit 1

CMD ["uvicorn", "app:APP", "--host", "0.0.0.0", "--port", "8082", "--workers", "2", "--proxy-headers"]
