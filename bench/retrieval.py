"""Runs MTEB's BelebeleRetrieval against an embedding row's /v1/embeddings.

bench/retrieval.sh validates the arguments and runs this file with the Python of the bench
environment's MTEB. This file refuses a subset BelebeleRetrieval doesn't define and a row that
doesn't serve `embedding`, before the first embedding request. It prepends the query prefix to
every query and the passage prefix to every passage, sends each batch of MTEB's as one request,
never asks the row to truncate, and stops at the first request the row refuses. It writes MTEB's
result, one score set a subset, under the output directory. See bench/README.md.
"""

import argparse
import sys

import mteb
import numpy as np
import requests
from mteb.models.abs_encoder import AbsEncoder
from mteb.models.model_meta import ModelMeta, ScoringFunction
from mteb.types import PromptType

TASK = "BelebeleRetrieval"
MODEL = "embedding"
BATCH_SIZE = 32
TIMEOUT = 300


class ServedEncoder(AbsEncoder):
    def __init__(self, url, served, query_prefix, passage_prefix):
        self.url = url
        self.prefixes = {PromptType.query: query_prefix, PromptType.document: passage_prefix}
        self.session = requests.Session()
        self.mteb_model_meta = ModelMeta.create_empty(
            overwrites={
                "name": served if "/" in served else f"served/{served}",
                "revision": MODEL,
                "modalities": ["text"],
                "similarity_fn_name": ScoringFunction.COSINE,
            }
        )

    def encode(self, inputs, *, task_metadata, hf_split, hf_subset, prompt_type=None, **kwargs):
        if prompt_type not in self.prefixes:
            raise RuntimeError(f"{task_metadata.name} {hf_subset} asked for prompt type {prompt_type}")
        prefix = self.prefixes[prompt_type]
        vectors = []
        for batch in inputs:
            texts = [prefix + text for text in batch["text"]]
            response = self.session.post(
                f"{self.url}/v1/embeddings",
                json={"model": MODEL, "input": texts, "encoding_format": "float"},
                timeout=TIMEOUT,
            )
            if not response.ok:
                raise RuntimeError(
                    f"{self.url} refused a batch of {hf_subset} {prompt_type} inputs "
                    f"({response.status_code}): {response.text[:2000]}"
                )
            data = sorted(response.json()["data"], key=lambda item: item["index"])
            if len(data) != len(texts):
                raise RuntimeError(f"{self.url} returned {len(data)} embeddings for {len(texts)} inputs")
            vectors.extend(item["embedding"] for item in data)
        return np.array(vectors, dtype=np.float32)


def refuse(message):
    print(f"retrieval: {message}", file=sys.stderr)
    sys.exit(2)


def main():
    parser = argparse.ArgumentParser(prog="bench/retrieval.py")
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--query-prefix", required=True)
    parser.add_argument("--passage-prefix", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("subsets", nargs="+")
    args = parser.parse_args()

    known = mteb.get_task(TASK).metadata.hf_subsets
    unknown = [subset for subset in args.subsets if subset not in known]
    if unknown:
        refuse(f"{TASK} has no subset {', '.join(unknown)}")

    url = f"http://{args.endpoint}"
    try:
        response = requests.get(f"{url}/v1/models", timeout=10)
        response.raise_for_status()
        models = {model["id"]: model for model in response.json()["data"]}
    except (requests.RequestException, KeyError, ValueError) as error:
        refuse(f"{url}/v1/models did not answer with a model list: {error}")
    if MODEL not in models:
        refuse(f"{url} serves {', '.join(models) or 'nothing'}, not {MODEL}")
    served = models[MODEL].get("root") or MODEL
    print(
        f"retrieval: {url} serves {MODEL} as {served}, context {models[MODEL].get('max_model_len')}",
        file=sys.stderr,
    )

    encoder = ServedEncoder(url, served, args.query_prefix, args.passage_prefix)
    task = mteb.get_task(TASK, hf_subsets=args.subsets)
    result = mteb.evaluate(
        encoder,
        task,
        co2_tracker=False,
        encode_kwargs={"batch_size": BATCH_SIZE},
        cache=mteb.ResultCache(cache_path=args.output),
        overwrite_strategy="always",
    )
    for task_result in result.task_results:
        for split, scores in task_result.scores.items():
            for score in scores:
                print(f"{score['hf_subset']}\t{split}\tndcg_at_10\t{score['ndcg_at_10']:.5f}")


if __name__ == "__main__":
    main()
