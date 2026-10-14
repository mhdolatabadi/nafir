FROM python:3.12-slim
RUN pip install --no-cache-dir faster-whisper==1.2.1
RUN useradd --uid 10001 --create-home transcriber && mkdir /models && chown transcriber /models
COPY service.py /app/service.py
USER transcriber
EXPOSE 8090
ENTRYPOINT ["python", "/app/service.py"]
