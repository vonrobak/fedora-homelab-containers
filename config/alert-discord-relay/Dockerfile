FROM python:3.11-slim

WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY relay.py .

# Create non-root user
RUN useradd -m -u 1000 relay && chown -R relay:relay /app
USER relay

# Expose port
EXPOSE 9095

# Run with gunicorn for production
CMD ["gunicorn", "--bind", "0.0.0.0:9095", "--workers", "2", "--timeout", "30", "relay:app"]
