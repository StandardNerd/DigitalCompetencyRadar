# Webscraper

A webscraper with the purpose of scraping job postings in the public sector and categorizing digital competencies, with a focus on skills analysis.

## Quickstart

Given Podman (or Docker) is installed and running.

1. Clone this repository

2. Build Container:

```bash
docker build --build-arg API_KEY='echo $API_KEY' -t webscraper .
```

3. ***Phase 1: Collect Job IDs***

Collect job IDs with a specified target count:

```bash
podman run --network=host -v $(pwd):/app webscraper ruby webscraper.rb --portal interamt --mode collect --collect-count 30
```

Set a custom checkpoint interval:

```bash
ruby webscraper.rb --portal interamt --mode collect --checkpoint-interval 10
```

Resume from a previous checkpoint:

```bash
ruby webscraper.rb --portal interamt --mode collect --resume-from checkpoint_latest.json
```

Combine these options as needed:

```bash
ruby webscraper.rb --portal interamt --mode collect --collect-count 8000 --checkpoint-interval 20 --resume-from checkpoint_id_collection_batch5_20250228_120000.json
```

4. ***Phase 2: Extract Job Details***

tbd in branch `feature/phase-2`


5. LLM API Test

Requirement:
The task requires the use of a personalized API key, which is stored as a shell environment variable (API_KEY). For example, the key can be set in your shell configuration file (.bashrc or .zshrc) as follows:

```bash
export API_KEY=your_api_key_here
```

The goal is to transmit the content of a job description (stored in a text file) to a Large Language Model (LLM) using a custom prompt. The LLM's response should then be saved to a file.

To achieve this, you can use the following podman command. This command mounts the current working directory into the container, passes the API_KEY environment variable, and executes the Ruby script api_test.rb:

```bash
podman run -v $(pwd):/app -e API_KEY=$(echo $API_KEY) webscraper ruby api_test.rb
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
