# Build llama.cpp-tq3 (TurboQuant) from source with CUDA support
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04 AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    curl \
    wget \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Clone TurboQuant fork and build
RUN git clone --depth 1 https://github.com/turbo-tan/llama.cpp-tq3.git /tmp/llama.cpp && \
    cd /tmp/llama.cpp && \
    cmake -B build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build --config Release -j$(nproc)

ENV PYTHONUNBUFFERED=1

# Set up the working directory
WORKDIR /

RUN apt-get update --yes --quiet && DEBIAN_FRONTEND=noninteractive apt-get install --yes --quiet --no-install-recommends \
    software-properties-common \
    gpg-agent \
    build-essential apt-utils \
    && apt-get install --reinstall ca-certificates \
    && add-apt-repository --yes ppa:deadsnakes/ppa && apt update --yes --quiet \
    && DEBIAN_FRONTEND=noninteractive apt-get install --yes --quiet --no-install-recommends \
    python3.11 \
    python3.11-dev \
    python3.11-distutils \
    python3.11-lib2to3 \
    python3.11-gdbm \
    python3.11-tk \
    bash \
    curl && \
    ln -s /usr/bin/python3.11 /usr/bin/python && \
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /work

# Add ./src as /work
ADD ./src /work

# Install runpod and its dependencies
RUN pip install -r ./requirements.txt && chmod +x /work/start.sh

# Copy the TurboQuant-enabled llama-server binary from builder
COPY --from=builder /tmp/llama.cpp/build/bin/llama-server /usr/local/bin/llama-server
COPY --from=builder /tmp/llama.cpp/build/bin/llama-cli /usr/local/bin/llama-cli

# Set the entrypoint
ENTRYPOINT ["/bin/sh", "-c", "/work/start.sh"]