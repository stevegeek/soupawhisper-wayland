#!/bin/bash
# Run SoupaWhisper with CUDA libraries

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export LD_LIBRARY_PATH=/usr/local/lib/ollama/cuda_v12:$LD_LIBRARY_PATH

exec "$SCRIPT_DIR/.venv/bin/python" "$SCRIPT_DIR/dictate.py" "$@"
