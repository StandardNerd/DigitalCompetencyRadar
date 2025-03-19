FROM ruby:3.2-slim

RUN apt-get update -qq && apt-get install -y \
    vim \
    build-essential \
    nodejs \
    wget \
    unzip \
    libxml2-dev \
    libxslt-dev \
    chromium \
    chromium-driver \
    libnss3 \
    libgconf-2-4 \
    libfontconfig1 \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install DuckDB
RUN curl -LO https://github.com/duckdb/duckdb/releases/download/v0.8.1/duckdb_cli-linux-amd64.zip \
    && unzip duckdb_cli-linux-amd64.zip -d /usr/local/bin \
    && rm duckdb_cli-linux-amd64.zip \
    && chmod +x /usr/local/bin/duckdb

WORKDIR /app

COPY Gemfile* ./

RUN bundle install

COPY . .

# Define a build-time argument
ARG API_KEY

# Set environment variables
ENV LANG=C.UTF-8 \
    CHROME_BIN=/usr/bin/chromium \
    CHROME_PATH=/usr/lib/chromium/ \
    CHROME_OPTIONS='--headless --no-sandbox --disable-dev-shm-usage --disable-gpu --disable-software-rasterizer' \
    API_KEY=$API_KEY

# Verify ChromeDriver installation
RUN chromedriver --version

# Verify DuckDB installation
RUN duckdb --version

# Command to run the scraper
CMD ["ruby", "webscraper.rb"]