import argparse
import json
from pathlib import Path

import torch
import torch.nn as nn
from torch.utils.data import DataLoader

from modules.data import (
    BalancedDomainBatchSampler,
    KSLDataset,
    build_signer_map,
    make_loso_split,
    read_manifest,
    validate_training_manifest,
)
from modules.features import INPUT_DIM
from modules.models import MaskedSequenceAutoencoder, SignLanguageModel, SignerClassifier
from modules.vocabulary import LABEL_MAP, NUM_CLASSES, WORDS


def mask_inputs(inputs, ratio):
    frame_mask = torch.rand(inputs.shape[:2], device=inputs.device) < ratio
    empty = ~frame_mask.any(dim=1)
    frame_mask[empty, 0] = True
    masked = inputs.clone()
    masked[frame_mask] = 0.0
    return masked, frame_mask


def run_stage0(model, loader, device, epochs, learning_rate, mask_ratio, output_dir):
    autoencoder = MaskedSequenceAutoencoder(model.encoder).to(device)
    optimizer = torch.optim.AdamW(autoencoder.parameters(), lr=learning_rate)
    history = []
    for epoch in range(1, epochs + 1):
        autoencoder.train()
        total_loss, total = 0.0, 0
        for batch in loader:
            target = batch["x"].to(device)
            inputs, frame_mask = mask_inputs(target, mask_ratio)
            optimizer.zero_grad()
            reconstructed = autoencoder(inputs)
            loss = (reconstructed[:, :, :450] - target[:, :, :450]).pow(2)
            loss = loss[frame_mask].mean()
            loss.backward()
            optimizer.step()
            total_loss += loss.item() * len(target)
            total += len(target)
        value = total_loss / max(total, 1)
        history.append(value)
        print(f"Stage 0 epoch {epoch:02d}: reconstruction_loss={value:.6f}")
    torch.save(model.encoder.state_dict(), output_dir / "stage0_encoder.pth")
    return history


def classification_epoch(
    model,
    loader,
    device,
    optimizer=None,
    signer_head=None,
    signer_weight=0.1,
    reversal_strength=0.1,
):
    training = optimizer is not None
    model.train(training)
    if training and not any(parameter.requires_grad for parameter in model.encoder.parameters()):
        model.encoder.eval()
    if signer_head is not None:
        signer_head.train(training)
    total_loss, correct, total = 0.0, 0, 0
    context = torch.enable_grad() if training else torch.no_grad()
    with context:
        for batch in loader:
            inputs = batch["x"].to(device)
            labels = batch["y"].to(device)
            if training:
                optimizer.zero_grad()
            features = model.encoder(inputs)
            logits = model.classifier(features)
            loss = nn.functional.cross_entropy(logits, labels)
            if signer_head is not None:
                signer_labels = batch["signer"].to(device)
                known = signer_labels >= 0
                if known.any():
                    signer_logits = signer_head(features[known], reversal_strength)
                    signer_loss = nn.functional.cross_entropy(signer_logits, signer_labels[known])
                    loss = loss + signer_weight * signer_loss
            if training:
                loss.backward()
                optimizer.step()
            total_loss += loss.item() * len(inputs)
            correct += (logits.argmax(dim=1) == labels).sum().item()
            total += len(inputs)
    return total_loss / max(total, 1), correct / max(total, 1)


def run_classification_stage(
    name,
    model,
    train_loader,
    validation_loader,
    optimizer,
    device,
    epochs,
    output_dir,
    signer_head=None,
    team_validation_loader=None,
):
    history = []
    best_accuracy = -1.0
    best_loss = float("inf")
    best_path = output_dir / f"{name}_best.pth"
    # Keep the pre-adaptation model if adaptation lowers validation performance.
    initial_loss, initial_accuracy = classification_epoch(model, validation_loader, device)
    best_accuracy, best_loss = initial_accuracy, initial_loss
    initial = {"epoch": 0, "validation_loss": initial_loss,
               "validation_accuracy": initial_accuracy}
    if team_validation_loader is not None:
        team_loss, team_accuracy = classification_epoch(model, team_validation_loader, device)
        best_accuracy = (initial_accuracy + team_accuracy) / 2
        best_loss = (initial_loss + team_loss) / 2
        initial.update(team_validation_loss=team_loss, team_validation_accuracy=team_accuracy)
    initial["selection_score"] = best_accuracy
    history.append(initial)
    torch.save({"model_state": model.state_dict(),
                "signer_state": signer_head.state_dict() if signer_head else None}, best_path)
    for epoch in range(1, epochs + 1):
        sampler = getattr(train_loader, "batch_sampler", None)
        if hasattr(sampler, "set_epoch"):
            sampler.set_epoch(epoch)
        train_loss, train_accuracy = classification_epoch(
            model, train_loader, device, optimizer, signer_head
        )
        validation_loss, validation_accuracy = classification_epoch(
            model, validation_loader, device
        )
        result = {
            "epoch": epoch,
            "train_loss": train_loss,
            "train_accuracy": train_accuracy,
            "validation_loss": validation_loss,
            "validation_accuracy": validation_accuracy,
        }
        selection_score = validation_accuracy
        selection_loss = validation_loss
        if team_validation_loader is not None:
            team_loss, team_accuracy = classification_epoch(model, team_validation_loader, device)
            result.update(team_validation_loss=team_loss, team_validation_accuracy=team_accuracy)
            selection_score = (validation_accuracy + team_accuracy) / 2
            selection_loss = (validation_loss + team_loss) / 2
        result["selection_score"] = selection_score
        history.append(result)
        print(
            f"{name} epoch {epoch:02d}: "
            f"train_loss={train_loss:.4f} train_acc={train_accuracy:.4f} "
            f"val_loss={validation_loss:.4f} val_acc={validation_accuracy:.4f} "
            f"team_val_acc={result.get('team_validation_accuracy', float('nan')):.4f}",
            flush=True,
        )
        # if validation_accuracy > best_accuracy:
        #     best_accuracy = validation_accuracy
        # Equal weight for expert and unseen validation signer during adaptation.
        if selection_score > best_accuracy or (selection_score == best_accuracy and selection_loss < best_loss):
            best_accuracy = selection_score
            best_loss = selection_loss
            torch.save(
                {
                    "model_state": model.state_dict(),
                    "signer_state": signer_head.state_dict() if signer_head else None,
                },
                best_path,
            )
    best = torch.load(best_path, map_location=device)
    model.load_state_dict(best["model_state"])
    if signer_head is not None and best["signer_state"] is not None:
        signer_head.load_state_dict(best["signer_state"])
    return history


def save_final_checkpoint(path, model, held_out_signer, signer_map):
    checkpoint = {
        "format_version": 2,
        "model_config": model.config,
        "feature_config": {
            "sequence_length": 30,
            "base_feature_dim": 150,
            "velocity_dim": 150,
            "acceleration_dim": 150,
            "hand_mask_dim": 2,
            "input_dim": INPUT_DIM,
        },
        "held_out_signer": held_out_signer,
        "signer_map": signer_map,
        "model_state": model.state_dict(),
        "label_map": LABEL_MAP,
        "word_dictionary": WORDS,
    }
    torch.save(checkpoint, path)


def main():
    parser = argparse.ArgumentParser(description="Four-stage LOSO sign-language training")
    # parser.add_argument("--manifest", type=Path, default=Path("data/processed/manifest.csv"))
    parser.add_argument("--manifest", type=Path, default=Path("data/processed_five/manifest.csv"))
    parser.add_argument("--held-out-signer", required=True)
    parser.add_argument("--validation-signer", required=True)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--export-path", type=Path)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--workers", type=int, default=0)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--stage0-epochs", type=int, default=20)
    parser.add_argument("--stage1-epochs", type=int, default=20)
    parser.add_argument("--stage2-epochs", type=int, default=10)
    parser.add_argument("--stage3-epochs", type=int, default=20)
    parser.add_argument("--mask-ratio", type=float, default=0.3)
    args = parser.parse_args()
    if args.batch_size <= 0 or args.batch_size % 2:
        parser.error("--batch-size must be a positive even number")
    if not 0.0 < args.mask_ratio < 1.0:
        parser.error("--mask-ratio must be between 0 and 1")

    torch.manual_seed(args.seed)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    samples = read_manifest(args.manifest)
    validate_training_manifest(samples)
    # splits = make_loso_split(samples, args.held_out_signer, seed=args.seed)
    splits = make_loso_split(samples, args.held_out_signer, seed=args.seed,
                             validation_signer=args.validation_signer)
    signer_map = build_signer_map(splits["stage0"])

    output_dir = args.output_dir or Path("models") / f"loso_{args.held_out_signer}"
    output_dir.mkdir(parents=True, exist_ok=True)

    datasets = {
        name: KSLDataset(rows, signer_map)
        for name, rows in splits.items()
        if name in {"stage0", "expert_train", "adapt_train", "validation", "team_validation"}
    }
    common = {"num_workers": args.workers, "pin_memory": device.type == "cuda"}
    stage0_loader = DataLoader(
        datasets["stage0"], batch_size=args.batch_size, shuffle=True, **common
    )
    expert_loader = DataLoader(
        datasets["expert_train"], batch_size=args.batch_size, shuffle=True, **common
    )
    validation_loader = DataLoader(
        datasets["validation"], batch_size=args.batch_size, shuffle=False, **common
    )
    team_validation_loader = DataLoader(datasets["team_validation"], batch_size=args.batch_size,
                                       shuffle=False, **common)
    balanced_sampler = BalancedDomainBatchSampler(
        splits["adapt_train"], batch_size=args.batch_size, seed=args.seed
    )
    adapt_loader = DataLoader(
        datasets["adapt_train"], batch_sampler=balanced_sampler, **common
    )

    # model = SignLanguageModel(num_classes=73, input_dim=INPUT_DIM).to(device)
    model = SignLanguageModel(num_classes=NUM_CLASSES, input_dim=INPUT_DIM).to(device)
    print(f"Device: {device}; classes: {NUM_CLASSES}; splits: "
          f"{ {name: len(rows) for name, rows in splits.items()} }", flush=True)
    history = {}
    history["stage0"] = run_stage0(
        model,
        stage0_loader,
        device,
        args.stage0_epochs,
        1e-3,
        args.mask_ratio,
        output_dir,
    )

    stage1_optimizer = torch.optim.AdamW(model.parameters(), lr=1e-3)
    history["stage1"] = run_classification_stage(
        "stage1",
        model,
        expert_loader,
        validation_loader,
        stage1_optimizer,
        device,
        args.stage1_epochs,
        output_dir,
    )
    save_final_checkpoint(output_dir / "expert_only.pth", model, args.held_out_signer, signer_map)

    for parameter in model.encoder.parameters():
        parameter.requires_grad = False
    stage2_optimizer = torch.optim.AdamW(model.classifier.parameters(), lr=5e-4)
    history["stage2"] = run_classification_stage(
        "stage2",
        model,
        adapt_loader,
        validation_loader,
        stage2_optimizer,
        device,
        args.stage2_epochs,
        output_dir,
        team_validation_loader=team_validation_loader,
    )

    for parameter in model.encoder.parameters():
        parameter.requires_grad = True
    signer_head = (
        SignerClassifier(model.config["hidden_dim"], len(signer_map)).to(device)
        if len(signer_map) > 1
        else None
    )
    parameters = list(model.parameters())
    if signer_head is not None:
        parameters += list(signer_head.parameters())
    stage3_optimizer = torch.optim.AdamW(parameters, lr=1e-4)
    history["stage3"] = run_classification_stage(
        "stage3",
        model,
        adapt_loader,
        validation_loader,
        stage3_optimizer,
        device,
        args.stage3_epochs,
        output_dir,
        signer_head,
        team_validation_loader=team_validation_loader,
    )

    final_path = output_dir / "final.pth"
    save_final_checkpoint(final_path, model, args.held_out_signer, signer_map)
    if args.export_path:
        args.export_path.parent.mkdir(parents=True, exist_ok=True)
        save_final_checkpoint(args.export_path, model, args.held_out_signer, signer_map)
    with (output_dir / "training_history.json").open("w", encoding="utf-8") as handle:
        json.dump(history, handle, ensure_ascii=False, indent=2)
    with (output_dir / "split_summary.json").open("w", encoding="utf-8") as handle:
        json.dump({"held_out_signer": args.held_out_signer,
                   "validation_signer": args.validation_signer,
                   "seed": args.seed,
                   "counts": {name: len(rows) for name, rows in splits.items()},
                   "training_signers": sorted(signer_map),
                   "label_map": LABEL_MAP, "words": WORDS}, handle, ensure_ascii=False, indent=2)
    print(f"Saved final checkpoint to {final_path}")


if __name__ == "__main__":
    main()
