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
        -DBUILD_SHARED_LIBS=ON \
        -DCMAKE_EXE_LINKER_FLAGS="-Wl,--allow-shlib-undefined" && \
    cmake --build . --config Release -j$(nproc) --target llama-server llama-cli || make -j$(nproc) llama-server llama-cli

# Runtime stage
FROM nvidia/cuda:12.8.0-runtime-ubuntu22.04

# Install runtime dependencies (CRITICAL FIX!)
# libgomp1 = OpenMP support (llama.cpp needs this)
# libstdc++6 = C++ standard library (TurboQuant build links against this)
RUN apt-get update && apt-get install -y \
    libgomp1 \
    libstdc++6 \
    libgcc1 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy TurboQuant binaries and shared libraries from builder
COPY --from=builder /tmp/llama.cpp/build/bin/ /app/
COPY --from=builder /tmp/llama.cpp/build/lib/ /app/

# Set up library path BEFORE ldconfig
RUN echo "/app" > /etc/ld.so.conf.d/app.conf && \
    ldconfig && \
    chmod +x /app/llama-server && \
    (chmod +x /app/llama-cli 2>/dev/null || true)

# Verify libraries loaded correctly (diagnostic check at build time)
RUN ldd /app/llama-server | grep "not found" && echo "ERROR: Missing dependencies!" && exit 1 || echo "✓ All dependencies found"

ENV LD_LIBRARY_PATH=/app:/usr/local/cuda/lib64:$LD_LIBRARY_PATH
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
