FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        ffmpeg \
        xterm \
        xvfb \
        x11-utils \
        x11-xserver-utils \
        xdotool \
    && rm -rf /var/lib/apt/lists/*
COPY betterdesk-agent /usr/local/bin/betterdesk-agent
COPY agent-config.example.json /etc/betterdesk-agent.json
COPY start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/betterdesk-agent /usr/local/bin/start.sh
ENTRYPOINT ["/usr/local/bin/start.sh"]
