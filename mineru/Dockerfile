# MinerU API server, CPU-only build for F3A (AMD iGPU, no CUDA).
#
# Pinned to mineru 3.1.11. Pipeline backend (no VLM, no GPU). Bakes the
# pipeline models into the image so cold-start is fast and offline-capable.
#
# Built by ubuntu/55_mineru.sh; runs as a sidecar to RagFlow.

FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    MINERU_MODEL_SOURCE=local

RUN apt-get update && apt-get install -y --no-install-recommends \
        fonts-noto-core fonts-noto-cjk fontconfig libgl1 libglib2.0-0 curl \
    && fc-cache -fv \
    && rm -rf /var/lib/apt/lists/*

# CPU-only PyTorch (avoids the multi-GB CUDA wheel)
RUN pip install --no-cache-dir \
        torch torchvision \
        --index-url https://download.pytorch.org/whl/cpu

# MinerU core (no vllm — VLM backends need GPU)
RUN pip install --no-cache-dir 'mineru[core]==3.1.11'

# Pre-download pipeline models into the image. Failure is non-fatal — at
# runtime, with MINERU_MODEL_SOURCE=local + a persistent volume mounted on
# /root/.cache/mineru, models will fetch on first start instead.
RUN mineru-models-download -s huggingface -m pipeline || true

EXPOSE 8000
ENTRYPOINT ["mineru-api"]
CMD ["--host", "0.0.0.0", "--port", "8000", "--backend", "pipeline"]
