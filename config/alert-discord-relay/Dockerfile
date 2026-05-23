# Base pinned by digest (ADR-030 P5). Tag at pin time: python:3.11-slim
FROM python:3.11-slim@sha256:a3ab0b966bc4e91546a033e22093cb840908979487a9fc0e6e38295747e49ac0

WORKDIR /app

# Hash-locked deps incl. full transitive tree (ADR-030 P5).
# Regenerate after editing requirements.txt (run inside the pinned base):
#   podman run --rm -v "$PWD:/work:Z" -w /work \
#     python:3.11-slim@sha256:a3ab0b966bc4e91546a033e22093cb840908979487a9fc0e6e38295747e49ac0 \
#     sh -c 'pip install -q pip-tools && pip-compile --generate-hashes \
#            --allow-unsafe -o requirements.lock requirements.txt'
COPY requirements.lock .
RUN pip install --no-cache-dir --require-hashes -r requirements.lock

# Copy application
COPY relay.py .

# Create non-root user
RUN useradd -m -u 1000 relay && chown -R relay:relay /app
USER relay

# Expose port
EXPOSE 9095

# Run with gunicorn for production
CMD ["gunicorn", "--bind", "0.0.0.0:9095", "--workers", "2", "--timeout", "30", "relay:app"]
