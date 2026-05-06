# Build llama.cpp-tq3 (TurboQuant) from source with CUDA support
FROM nvidia/cuda:12.8.0-devel-ubuntu22.04 AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    curl \
    wget \
    python3 \
    python3-pip \
    ccache \
    && rm -rf /var/lib/apt/lists/*

# Verify cmake and CUDA are available
RUN cmake --version && nvcc --version

# Clone TurboQuant fork
RUN git clone https://github.com/TheTom/llama-cpp-turboquant.git /tmp/llama.cpp

# Build with explicit CUDA paths
# Build with explicit CUDA paths and persistent ccache
RUN --mount=type=cache,target=/ccache \
    export CCACHE_DIR=/ccache && \
    cd /tmp/llama.cpp && \
    mkdir -p build && cd build && \
    cmake .. \
        -DGGML_CUDA=ON \
        -DCMAKE_CUDA_ARCHITECTURES="100" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc \
        -DGGML_CCACHE=ON \
        -DLLAMA_BUILD_EXAMPLES=OFF \
        -DLLAMA_BUILD_TESTS=OFF \
        -DCMAKE_EXE_LINKER_FLAGS="-L/usr/local/cuda/lib64/stubs" && \
    cmake --build . --config Release -j$(nproc) || make -j$(nproc)

# Runtime stage
FROM nvidia/cuda:12.8.0-runtime-ubuntu22.04

# Copy TurboQuant binaries from builder
COPY --from=builder /tmp/llama.cpp/build/bin/llama-server /usr/local/bin/llama-server
COPY --from=builder /tmp/llama.cpp/build/bin/llama-cli /usr/local/bin/llama-cli

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

# Set the entrypoint
ENTRYPOINT ["/bin/sh", "-c", "/work/start.sh"]
