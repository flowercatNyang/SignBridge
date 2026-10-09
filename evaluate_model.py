import argparse
import json
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import DataLoader

from modules.data import KSLDataset, read_manifest
from modules.models import SignLanguageModel


def macro_f1(labels, predictions, num_classes):
    scores = []
    for class_index in range(num_classes):
        true_positive = np.sum((labels == class_index) & (predictions == class_index))
        false_positive = np.sum((labels != class_index) & (predictions == class_index))
        false_negative = np.sum((labels == class_index) & (predictions != class_index))
        denominator = 2 * true_positive + false_positive + false_negative
        scores.append(0.0 if denominator == 0 else 2 * true_positive / denominator)
    return float(np.mean(scores))


def evaluate(model, samples, device, batch_size):
    if not samples:
        return None
    loader = DataLoader(KSLDataset(samples), batch_size=batch_size, shuffle=False)
    labels, top5 = [], []
    model.eval()
    with torch.no_grad():
        for batch in loader:
            logits = model(batch["x"].to(device))
            k = min(5, logits.shape[1])
            top5.append(logits.topk(k, dim=1).indices.cpu().numpy())
            labels.append(batch["y"].numpy())
    labels = np.concatenate(labels)
    top5 = np.concatenate(top5)
    predictions = top5[:, 0]
    result = {
        "samples": int(len(labels)),
        "top1_accuracy": float(np.mean(predictions == labels)),
        "top3_accuracy": float(np.mean([label in row[:3] for label, row in zip(labels, top5)])),
        "top5_accuracy": float(np.mean([label in row for label, row in zip(labels, top5)])),
        "macro_f1": macro_f1(labels, predictions, model.config["num_classes"]),
    }
    confusion = np.zeros((model.config["num_classes"], model.config["num_classes"]), dtype=int)
    np.add.at(confusion, (labels, predictions), 1)
    result["confusion_matrix"] = confusion.tolist()
    result["per_class"] = {
        str(label): {"samples": int(np.sum(labels == label)),
                     "correct": int(np.sum((labels == label) & (predictions == label)))}
        for label in sorted(set(labels.tolist()))
    }
    result["predictions"] = [
        {"source_sequence": str(sample.path), "true_label": int(label),
         "predicted_label": int(prediction), "top3": row[:3].tolist()}
        for sample, label, prediction, row in zip(samples, labels, predictions, top5)
    ]
    return result


def main():
    parser = argparse.ArgumentParser(description="Evaluate a LOSO checkpoint")
    parser.add_argument("--checkpoint", type=Path, required=True)
    # parser.add_argument("--manifest", type=Path, default=Path("data/processed/manifest.csv"))
    parser.add_argument("--manifest", type=Path, default=Path("data/processed_five/manifest.csv"))
    parser.add_argument("--held-out-signer")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--batch-size", type=int, default=64)
    args = parser.parse_args()

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    checkpoint = torch.load(args.checkpoint, map_location=device)
    if checkpoint.get("format_version") != 2:
        raise ValueError("This evaluator requires a format_version=2 checkpoint")
    model = SignLanguageModel(**checkpoint["model_config"]).to(device)
    model.load_state_dict(checkpoint["model_state"])

    held_out_signer = args.held_out_signer or checkpoint.get("held_out_signer")
    samples = read_manifest(args.manifest)
    held_out = [
        sample
        for sample in samples
        if sample.domain == "team" and sample.signer_id == held_out_signer
    ]
    external = [sample for sample in samples if sample.domain == "external"]
    report = {
        "checkpoint": str(args.checkpoint.resolve()),
        "word_dictionary": checkpoint.get("word_dictionary", {}),
        "label_map": checkpoint.get("label_map", {}),
        "held_out_signer": held_out_signer,
        "held_out_team": evaluate(model, held_out, device, args.batch_size),
        "external_fixed_test": evaluate(model, external, device, args.batch_size),
    }
    output_path = args.output or args.checkpoint.with_name("evaluation.json")
    output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: ({k: v for k, v in value.items() if k != "predictions"}
                           if key in {"held_out_team", "external_fixed_test"} and value else value)
                      for key, value in report.items()}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
