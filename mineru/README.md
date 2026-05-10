# MinerU API server (F3A)

CPU-only, pinned to mineru 3.1.11. Sits on the `ragflow` Docker network as
service `mineru-api`. RagFlow calls it via `MINERU_APISERVER`.

## Why we run our own image

Upstream `opendatalab/mineru` only ships a CUDA Dockerfile. F3A is AMD iGPU
(Vulkan), so we build a slim CPU image: Python 3.11 + CPU-only PyTorch +
`mineru[core]` + the pipeline models pre-baked. ~6 GB final image.

## Build + run

```bash
bash ubuntu/55_mineru.sh        # builds the image, starts the service
```

The build pulls ~3 GB (PyTorch CPU, MinerU + transformers, fonts) and runs
`mineru-models-download -s huggingface -m pipeline` once during build —
~5-10 min on a fast connection, then cached as an image layer.

## Endpoints

- `GET  /openapi.json`   — health check (RagFlow uses this to verify reachability)
- `POST /file_parse`     — multipart PDF upload, returns ZIP of Markdown + JSON
- `GET  /docs`           — interactive Swagger UI

## RagFlow wiring

`~/.env` on F3A:
```
MINERU_APISERVER=http://mineru-api:8000   # internal service name
MINERU_BACKEND=pipeline
```

For each tenant, register a MinerU OCR entry in `tenant_llm`:
```sql
INSERT INTO tenant_llm
  (tenant_id, llm_factory, model_type, llm_name, api_base, status, ...)
VALUES
  ('<tid>', 'MinerU', 'ocr', 'mineru-pipeline',
   'http://mineru-api:8000', '1', ...);
```

Then for the dataset/document you want parsed via MinerU, set:
```json
"layout_recognize": "mineru-pipeline@mineru"
```
in `parser_config` (via DB UPDATE — RagFlow's POST API rejects this field).

## Smoke test

```bash
curl -s -X POST http://192.168.1.13:8100/file_parse \
  -F 'files=@your.pdf;type=application/pdf' \
  -F 'backend=pipeline' \
  -F 'parse_method=auto' \
  -F 'return_md=true' \
  -F 'response_format_zip=true' \
  -o /tmp/out.zip
unzip -p /tmp/out.zip '*.md' | head
```

Host port 8100 → container 8000 (avoids clash with MinIO at 9000).

## Notes

- First parse cold-loads ~3 GB of models into RAM (~30-60 s).
- Subsequent parses ~30-120 s for a 10-20 page PDF on F3A's CPU.
- For German texts: PaddleOCR (used internally by MinerU) handles Umlauts
  and ß correctly out of the box. No `lang` configuration needed.
- All five MinerU stages (layout, reading order, OCR, tables, formulas)
  run on CPU. No GPU.
- VLM backends (`vlm-transformers`, `vlm-vllm-engine`, `vlm-sglang-engine`)
  require CUDA and aren't usable on this hardware.
