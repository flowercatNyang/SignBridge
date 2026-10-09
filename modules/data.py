import csv
import math
import random
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import Dataset, Sampler

from .features import INPUT_DIM, SEQUENCE_LENGTH
from .vocabulary import EXPECTED_PER_CLASS, LABEL_MAP, NUM_CLASSES


DOMAIN_TO_ID = {"expert": 0, "team": 1, "external": 2}


@dataclass(frozen=True)
class Sample:
    path: Path
    label: int
    class_key: str
    domain: str
    signer_id: str


def read_manifest(manifest_path):
    manifest_path = Path(manifest_path)
    with manifest_path.open("r", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    samples = [
        Sample(
            path=(manifest_path.parent / row["path"]).resolve(),
            label=int(row["label"]),
            class_key=row["class_key"],
            domain=row["domain"],
            signer_id=row["signer_id"],
        )
        for row in rows
    ]
    if not samples:
        raise ValueError("The manifest is empty. Run preprocess_videos.py first.")
    return samples


# def validate_training_manifest(samples, num_classes=73):
def validate_training_manifest(samples, num_classes=NUM_CLASSES):
    for sample in samples:
        if sample.class_key not in LABEL_MAP or LABEL_MAP[sample.class_key] != sample.label:
            raise ValueError(f"Manifest vocabulary mismatch: {sample.class_key}/{sample.label}")
    labels = {sample.label for sample in samples if sample.domain != "external"}
    if labels != set(range(num_classes)):
        raise ValueError(f"Expected labels 0..{num_classes - 1}, found {len(labels)} classes")
    # for domain, minimum in (("expert", 50), ("team", 9)):
    for domain, minimum in EXPECTED_PER_CLASS.items():
        for label in range(num_classes):
            count = sum(sample.domain == domain and sample.label == label for sample in samples)
            if count < minimum:
                raise ValueError(
                    f"{domain} label {label} has {count} samples; at least {minimum} are required"
                )


def make_loso_split(samples, held_out_signer, validation_fraction=0.1, seed=42, validation_signer=None):
    held_out = [
        sample
        for sample in samples
        if sample.domain == "team" and sample.signer_id == held_out_signer
    ]
    if not held_out:
        raise ValueError(f"No team samples found for held-out signer: {held_out_signer}")
    if validation_signer == held_out_signer:
        raise ValueError("Validation signer and test signer must differ")

    rng = random.Random(seed)
    expert_by_class = defaultdict(list)
    team_train, team_validation = [], []
    external = []
    for sample in samples:
        if sample.domain == "expert":
            expert_by_class[sample.label].append(sample)
        elif sample.domain == "team" and sample.signer_id == validation_signer:
            team_validation.append(sample)
        elif sample.domain == "team" and sample.signer_id != held_out_signer:
            team_train.append(sample)
        elif sample.domain == "external":
            external.append(sample)

    expert_train, validation = [], []
    for label_samples in expert_by_class.values():
        rng.shuffle(label_samples)
        count = max(1, int(round(len(label_samples) * validation_fraction)))
        validation.extend(label_samples[:count])
        expert_train.extend(label_samples[count:])
    if validation_signer and not team_validation:
        raise ValueError(f"No videos for validation signer {validation_signer}")
    return {
        "stage0": expert_train + team_train,
        "expert_train": expert_train,
        "adapt_train": expert_train + team_train,
        "validation": validation,
        "team_validation": team_validation,
        "held_out": held_out,
        "external": external,
    }


def build_signer_map(samples):
    signer_ids = sorted(
        {
            sample.signer_id
            for sample in samples
            if sample.signer_id and not sample.signer_id.endswith("_unknown")
        }
    )
    return {signer_id: index for index, signer_id in enumerate(signer_ids)}


class KSLDataset(Dataset):
    def __init__(self, samples, signer_map=None):
        self.samples = list(samples)
        self.signer_map = signer_map or {}

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, index):
        sample = self.samples[index]
        with np.load(sample.path) as data:
            sequence = data["x"].astype(np.float32)
        if sequence.shape != (SEQUENCE_LENGTH, INPUT_DIM):
            raise ValueError(
                f"{sample.path} has shape {sequence.shape}; expected {(SEQUENCE_LENGTH, INPUT_DIM)}"
            )
        return {
            "x": torch.from_numpy(sequence),
            "y": torch.tensor(sample.label, dtype=torch.long),
            "domain": torch.tensor(DOMAIN_TO_ID[sample.domain], dtype=torch.long),
            "signer": torch.tensor(self.signer_map.get(sample.signer_id, -1), dtype=torch.long),
        }


class BalancedDomainBatchSampler(Sampler):
    def __init__(self, samples, batch_size=64, seed=42):
        if batch_size % 2:
            raise ValueError("batch_size must be even for 1:1 expert/team batches")
        self.batch_size = batch_size
        self.half = batch_size // 2
        self.seed = seed
        self.epoch = 0
        self.by_domain_class = {"expert": defaultdict(list), "team": defaultdict(list)}
        for index, sample in enumerate(samples):
            if sample.domain in self.by_domain_class:
                self.by_domain_class[sample.domain][sample.label].append(index)
        if not self.by_domain_class["expert"] or not self.by_domain_class["team"]:
            raise ValueError("Balanced batches require both expert and team samples")
        domain_sizes = [
            sum(len(indices) for indices in groups.values())
            for groups in self.by_domain_class.values()
        ]
        self.num_batches = math.ceil(max(domain_sizes) / self.half)

    def __len__(self):
        return self.num_batches

    def set_epoch(self, epoch):
        self.epoch = epoch

    def _draw(self, domain, count, rng, positions, pools, cursors):
        labels = sorted(pools[domain])
        result = []
        for offset in range(count):
            label = labels[(positions[domain] + offset) % len(labels)]
            if cursors[domain][label] >= len(pools[domain][label]):
                rng.shuffle(pools[domain][label])
                cursors[domain][label] = 0
            result.append(pools[domain][label][cursors[domain][label]])
            cursors[domain][label] += 1
        positions[domain] += count
        return result

    def __iter__(self):
        rng = random.Random(self.seed + self.epoch)
        pools = {
            domain: {label: list(indices) for label, indices in groups.items()}
            for domain, groups in self.by_domain_class.items()
        }
        for groups in pools.values():
            for indices in groups.values():
                rng.shuffle(indices)
        cursors = {
            domain: {label: 0 for label in groups}
            for domain, groups in pools.items()
        }
        positions = {
            domain: rng.randrange(len(groups))
            for domain, groups in pools.items()
        }
        for _ in range(self.num_batches):
            batch = self._draw(
                "expert", self.half, rng, positions, pools, cursors
            )
            batch += self._draw(
                "team", self.half, rng, positions, pools, cursors
            )
            rng.shuffle(batch)
            yield batch
