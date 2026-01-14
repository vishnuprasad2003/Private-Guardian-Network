FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y curl wget jq && rm -rf /var/lib/apt/lists/*

# Install Foundry (for Anvil)
RUN curl -L https://foundry.paradigm.xyz | bash && /root/.foundry/bin/foundryup
ENV PATH="/root/.foundry/bin:$PATH"

WORKDIR /app
COPY scripts/ /app/scripts/
COPY configs/ /app/configs/
COPY contracts/ /app/contracts/
RUN chmod +x /app/scripts/*.sh && mkdir -p /app/data /app/logs /app/keys

ENV WORKSPACE_ROOT=/app
ENTRYPOINT ["/app/scripts/start-guardian.sh"]
CMD ["/app/configs/guardian-0.conf"]
