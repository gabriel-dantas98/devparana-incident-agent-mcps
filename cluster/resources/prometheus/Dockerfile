FROM python:3.11-slim

WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir flask requests

# Copy the webhook proxy script
COPY discord-webhook-proxy.py .

# Expose port
EXPOSE 8080

# Run the application
CMD ["python", "discord-webhook-proxy.py"]
