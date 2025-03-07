# Use Ruby 3.2 as the base image
FROM ruby:3.2-slim

# Install essential Linux packages
RUN apt-get update -qq && apt-get install -y \
    vim \
    build-essential \
    nodejs \
    wget \
    unzip \
    # Required for nokogiri
    libxml2-dev \
    libxslt-dev \
    # Required for Chrome
    chromium \
    chromium-driver \
    libnss3 \
    libgconf-2-4 \
    libfontconfig1 \
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Create Gemfile
COPY Gemfile* ./

# Install gems
RUN bundle install

# Copy the rest of the application
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

# Command to run the scraper
CMD ["ruby", "webscraper.rb"]
