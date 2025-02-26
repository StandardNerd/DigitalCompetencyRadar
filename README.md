# Webscraper

A webscraper with the purpose of scraping job postings in the public sector and categorizing digital competencies, with a focus on skills analysis.

## Quickstart

Given Podman (or Docker) is installed and running.

1. Clone this repository

2. Build Container:

```bash
podman build -t webscraper .
```

3. Run Webscraper:

```bash
podman run -v $(pwd):/app webscraper ruby webscraper.rb --portal interamt
```

or in case of "Your connection was interrupted" error in the Docker container's browser:

```bash
podman run --network=host -v $(pwd):/app webscraper ruby webscraper.rb --portal interamt
```

The webscraper parses the first three job postings – a screenshot of the job listing is also taken – and creates a folder called "scraped_data_interamt" (or "scraped_data_bund" if portal `bund` is used) containing three parsed job postings in separate text files with html code, including the screenshot. The screenshots are for debugging purposes.

4. Webscraper Options:


```bash
Basic Usage:
  ruby webscraper.rb --portal [bund|interamt]

Examples:
  ruby webscraper.rb --portal interamt --keyword "Informatiker" --results 8
  ruby webscraper.rb --portal bund --keyword "Sachbearbeiter" --results 12

Available Options:
        --portal PORTAL              Required. Specify which job portal to scrape
                                       bund    - service.bund.de Portal
                                       interamt - interamt.de Portal
        --keyword KEYWORD            Search keyword
        --results N                  Number of results to process
                                       Default: 1
        --help                       Show this help message
        --version                    Show version
```

## Podman/Docker Cheatsheet

Build the image: `podman build -t webscraper .`

Run the container: `podman run --network=host webscraper ruby webscraper.rb --portal interamt`

Start the container and login into a Bash shell inside the container: `podman run --network=host -it webscraper /bin/bash`

List running containers: `podman ps`

Stop a container: `podman stop <container_id>`

Remove a container: `podman rm <container_id>`

Remove an image: `podman rmi webscraper`

The Podman commands are identical to that of Docker.
