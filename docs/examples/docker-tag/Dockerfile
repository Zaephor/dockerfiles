FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

LABEL org.opencontainers.image.description="Example Python application based on Docker registry base image"

ENTRYPOINT ["python", "-m", "app"]
CMD ["--version"]
