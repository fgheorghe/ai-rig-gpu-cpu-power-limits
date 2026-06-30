FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends crudini \
    && rm -rf /var/lib/apt/lists/*
COPY gpu_power_limit.sh /usr/local/bin/gpu_power_limit.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/gpu_power_limit.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
