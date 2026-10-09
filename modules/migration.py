import numpy as np

from .features import (
    BASE_FEATURE_DIM,
    INPUT_DIM,
    LEFT_HAND_SLICE,
    RIGHT_HAND_SLICE,
    SEQUENCE_LENGTH,
    build_temporal_features,
)


def infer_hand_masks(frame_features):
    frame_features = np.asarray(frame_features, dtype=np.float32)
    right = np.any(np.abs(frame_features[:, RIGHT_HAND_SLICE]) > 1e-8, axis=1)
    left = np.any(np.abs(frame_features[:, LEFT_HAND_SLICE]) > 1e-8, axis=1)
    return np.stack([right, left], axis=1).astype(np.float32)


def convert_expert_sequence(sequence):
    sequence = np.asarray(sequence, dtype=np.float32)
    if sequence.ndim != 2:
        raise ValueError(f"Each sequence must be 2D, found shape {sequence.shape}")
    if not np.isfinite(sequence).all():
        raise ValueError("Sequence contains NaN or infinite values")

    if sequence.shape[1] == INPUT_DIM:
        if len(sequence) != SEQUENCE_LENGTH:
            raise ValueError(
                f"Existing {INPUT_DIM}D sequence must have {SEQUENCE_LENGTH} frames, "
                f"found {len(sequence)}"
            )
        return sequence.copy()
    if sequence.shape[1] != BASE_FEATURE_DIM:
        raise ValueError(
            f"Expected feature dimension {BASE_FEATURE_DIM} or {INPUT_DIM}, "
            f"found {sequence.shape[1]}"
        )

    masks = infer_hand_masks(sequence)
    return build_temporal_features(sequence, masks)
