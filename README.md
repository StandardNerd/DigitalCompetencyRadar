# Webscraper

A webscraper with the purpose of scraping job postings in the public sector and categorizing digital competencies, with a focus on skills analysis.

## Quickstart

Given Podman (or Docker) is installed and running.

1. Clone this repository

2. Build Container:

```bash
docker build --build-arg API_KEY='echo $API_KEY' -t webscraper .
```

3. Run Webscraper:

```bash
podman run -v $(pwd):/app webscraper ruby webscraper.rb --portal interamt --max-jobs 30
```

or in case of "Your connection was interrupted" error in the Docker container's browser:

```bash
podman run --network=host -v $(pwd):/app webscraper ruby webscraper.rb --portal interamt --max-jobs 30
```

4. Convert HTML files to text files using LLM-API Call:

```bash
podman run -v $(pwd):/app webscraper ruby html2txt.rb
```

5. Classify required skills in job description (from text files) using LLM-API Call:

```bash
podman run -v $(pwd):/app webscraper ruby digcomp_classification.rb
```

