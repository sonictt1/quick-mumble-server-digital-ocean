FROM ubuntu:22.04

# Install dependencies
RUN apt-get update -qq && \
    apt-get install -yq curl jq openssh-client bash && \
    curl -sL https://github.com/digitalocean/doctl/releases/latest/download/doctl-1.104.0-linux-amd64.tar.gz | tar -xz -C /usr/local/bin && \
    chmod +x /usr/local/bin/doctl

# Copy your script into the container
COPY inflate_murmur.sh /inflate_murmur.sh

# Make sure the script is executable
RUN chmod +x /inflate_murmur.sh

# Declare the SSH volume
VOLUME ["/root/.ssh"]

# Set entrypoint
ENTRYPOINT ["/inflate_murmur.sh"]