# The audio image, ai-hosting/vllm-openai-rocm-audio: vLLM's ROCm image at the pinned release, by
# its digest, with the decoders of vLLM's audio extra it ships without, which the strix-halo audio
# row serves from. hosting engine install and update build it, tagged with the release.
# See context/engines.md, "The audio image".
# Adapted from spike-model-engines (6ce3210): host/vllm-rocm-audio/Dockerfile, named under
# ai-hosting, with ENV MIOPEN_FIND_MODE=FAST, which that commit lacks.
FROM vllm/vllm-openai-rocm:v0.34.0@sha256:3cb773d23f063afa86291ef75773cdd486154ddea94c213300f4ed7cc42b7af1
RUN uv pip install --system av==19.0.2 soundfile==0.14.0 soxr==1.1.0
ENV MIOPEN_FIND_MODE=FAST
