# Use an explicit, patched base image (avoid floating "slim").
FROM python:3.11.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

# Set working directory
WORKDIR /app

# Pull in Debian security updates, then remove apt lists.
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency list
COPY requirements.txt .

# Upgrade Python packaging tooling to patched versions (scanners commonly flag old defaults).
RUN python -m pip install --upgrade pip setuptools wheel

# Install dependencies
RUN pip install -r requirements.txt

# Copy application code
COPY . .

# Drop root
RUN useradd --system --uid 10001 --create-home appuser \
    && chown -R appuser:appuser /app
USER appuser

# Expose Flask port
EXPOSE 5000

# Start the Flask application
CMD ["python", "app.py"]