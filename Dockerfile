FROM nvidia/cuda:12.6.0-base-ubuntu24.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends bash coreutils crudini && \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY gpu_power_limit.sh /usr/local/bin/gpu_power_limit.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/gpu_power_limit.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
