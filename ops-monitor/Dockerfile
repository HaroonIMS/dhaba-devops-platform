
# Stage 1: Download and verify kubectl.
FROM debian:bookworm-slim AS tools

ARG KUBECTL_VERSION=v1.37.2

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64|arm64) ;; \
      *) echo "Unsupported architecture: $ARCH"; exit 1 ;; \
    esac; \
    curl -fsSLo /tmp/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"; \
    curl -fsSLo /tmp/kubectl.sha256 \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl.sha256"; \
    echo "$(cat /tmp/kubectl.sha256)  /tmp/kubectl" | sha256sum -c -; \
    install -m 0755 /tmp/kubectl /usr/local/bin/kubectl; \
    rm -f /tmp/kubectl /tmp/kubectl.sha256

# Stage 2: Monitoring runtime.
FROM debian:bookworm-slim

ARG VERSION=unknown

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash \
      curl \
      ca-certificates \
      postgresql-client \
      redis-tools \
      jq \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system ops \
 && useradd --system \
      --gid ops \
      --home-dir /home/ops \
      --create-home ops

COPY --from=tools /usr/local/bin/kubectl /usr/local/bin/kubectl

COPY --chown=ops:ops scripts/monitor/ /opt/monitor/

RUN chmod 0755 /opt/monitor/*.sh

ENV VERSION=${VERSION}
ENV HOME=/home/ops

WORKDIR /opt/monitor

USER ops

# Run the complete monitoring controller.
CMD ["/opt/monitor/ops-monitor.sh"]
