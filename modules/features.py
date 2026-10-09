import numpy as np


BASE_FEATURE_DIM = 150
HAND_MASK_DIM = 2
INPUT_DIM = BASE_FEATURE_DIM * 3 + HAND_MASK_DIM
SEQUENCE_LENGTH = 30

H_PARENTS = [0, 1, 2, 3, 0, 5, 6, 7, 0, 9, 10, 11, 0, 13, 14, 15, 0, 17, 18, 19]
H_CHILDREN = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
UB_PARENTS = [1, 1, 2, 3, 1, 5, 6]
UB_CHILDREN = [0, 2, 3, 4, 5, 6, 7]
RIGHT_HAND_SLICE = slice(0, 63)
LEFT_HAND_SLICE = slice(63, 126)


def compute_25d_features(coords, parents, children, angle_v1, angle_v2):
    coords = np.asarray(coords, dtype=np.float32)
    if not np.any(coords):
        return np.zeros(len(parents) * 3 + len(angle_v1), dtype=np.float32)

    bones = coords[children] - coords[parents]
    dx, dy, dz = bones[:, 0], bones[:, 1], bones[:, 2]
    norm2d = np.sqrt(dx**2 + dy**2) + 1e-6
    v1, v2 = bones[angle_v1, :2], bones[angle_v2, :2]
    dot = np.sum(v1 * v2, axis=1)
    denom = np.linalg.norm(v1, axis=1) * np.linalg.norm(v2, axis=1) + 1e-6
    angles = np.arccos(np.clip(dot / denom, -1.0, 1.0))
    return np.concatenate([dx / norm2d, dy / norm2d, dz, angles]).astype(np.float32)


def extract_keypoints(results, width, height, return_mask=False):
    pose = np.zeros((8, 3), dtype=np.float32)
    if results.pose_landmarks:
        landmarks = results.pose_landmarks.landmark
        pose[0] = [landmarks[0].x * width, landmarks[0].y * height, landmarks[0].z * width]
        left_shoulder = np.array(
            [landmarks[11].x * width, landmarks[11].y * height, landmarks[11].z * width],
            dtype=np.float32,
        )
        right_shoulder = np.array(
            [landmarks[12].x * width, landmarks[12].y * height, landmarks[12].z * width],
            dtype=np.float32,
        )
        pose[1] = (left_shoulder + right_shoulder) / 2.0
        pose[2] = right_shoulder
        pose[3] = [landmarks[14].x * width, landmarks[14].y * height, landmarks[14].z * width]
        pose[4] = [landmarks[16].x * width, landmarks[16].y * height, landmarks[16].z * width]
        pose[5] = left_shoulder
        pose[6] = [landmarks[13].x * width, landmarks[13].y * height, landmarks[13].z * width]
        pose[7] = [landmarks[15].x * width, landmarks[15].y * height, landmarks[15].z * width]

    right_detected = results.right_hand_landmarks is not None
    left_detected = results.left_hand_landmarks is not None
    right_hand = _hand_coordinates(results.right_hand_landmarks, width, height)
    left_hand = _hand_coordinates(results.left_hand_landmarks, width, height)

    neck = pose[1].copy()
    pose -= neck
    if right_detected:
        right_hand -= neck
    if left_detected:
        left_hand -= neck

    shoulder_width = np.linalg.norm(pose[5] - pose[2])
    if shoulder_width < 1e-6:
        shoulder_width = 1.0
    pose /= shoulder_width
    if right_detected:
        right_hand /= shoulder_width
    if left_detected:
        left_hand /= shoulder_width

    right_features = compute_25d_features(right_hand, H_PARENTS, H_CHILDREN, [0, 4, 8], [1, 5, 9])
    left_features = compute_25d_features(left_hand, H_PARENTS, H_CHILDREN, [0, 4, 8], [1, 5, 9])
    body_features = compute_25d_features(pose, UB_PARENTS, UB_CHILDREN, [2, 5, 1], [3, 6, 4])
    features = np.concatenate([right_features, left_features, body_features]).astype(np.float32)
    mask = np.array([right_detected, left_detected], dtype=np.float32)
    return (features, mask) if return_mask else features


def _hand_coordinates(hand_landmarks, width, height):
    coords = np.zeros((21, 3), dtype=np.float32)
    if hand_landmarks:
        for index, landmark in enumerate(hand_landmarks.landmark):
            coords[index] = [landmark.x * width, landmark.y * height, landmark.z * width]
    return coords


def _interpolate_block(values, detected):
    valid = np.flatnonzero(detected > 0.5)
    if len(valid) == 0:
        return values
    if len(valid) == 1:
        values[:] = values[valid[0]]
        return values
    target = np.arange(len(values))
    for column in range(values.shape[1]):
        values[:, column] = np.interp(target, valid, values[valid, column])
    return values


def interpolate_missing_hands(frame_features, hand_masks):
    frame_features = np.asarray(frame_features, dtype=np.float32).copy()
    hand_masks = np.asarray(hand_masks, dtype=np.float32)
    frame_features[:, RIGHT_HAND_SLICE] = _interpolate_block(
        frame_features[:, RIGHT_HAND_SLICE], hand_masks[:, 0]
    )
    frame_features[:, LEFT_HAND_SLICE] = _interpolate_block(
        frame_features[:, LEFT_HAND_SLICE], hand_masks[:, 1]
    )
    return frame_features


def _resample(values, length):
    if len(values) == length:
        return values.astype(np.float32, copy=False)
    if len(values) == 1:
        return np.repeat(values, length, axis=0).astype(np.float32)
    source = np.linspace(0.0, 1.0, len(values))
    target = np.linspace(0.0, 1.0, length)
    columns = [np.interp(target, source, values[:, column]) for column in range(values.shape[1])]
    return np.stack(columns, axis=1).astype(np.float32)


def build_temporal_features(frame_features, hand_masks, sequence_length=SEQUENCE_LENGTH):
    frame_features = np.asarray(frame_features, dtype=np.float32)
    hand_masks = np.asarray(hand_masks, dtype=np.float32)
    if frame_features.ndim != 2 or frame_features.shape[1] != BASE_FEATURE_DIM:
        raise ValueError(f"frame_features must have shape [T, {BASE_FEATURE_DIM}]")
    if hand_masks.shape != (len(frame_features), HAND_MASK_DIM):
        raise ValueError(f"hand_masks must have shape [T, {HAND_MASK_DIM}]")
    if len(frame_features) == 0:
        raise ValueError("At least one frame is required")

    base = interpolate_missing_hands(frame_features, hand_masks)
    base = _resample(base, sequence_length)
    masks = _resample(hand_masks, sequence_length)
    velocity = np.diff(base, axis=0, prepend=base[:1])
    acceleration = np.diff(velocity, axis=0, prepend=velocity[:1])
    return np.concatenate([base, velocity, acceleration, masks], axis=1).astype(np.float32)


def motion_energy(sequence):
    sequence = np.asarray(sequence, dtype=np.float32)
    if sequence.ndim != 2 or sequence.shape[1] < BASE_FEATURE_DIM * 2:
        return 0.0
    velocity = sequence[:, BASE_FEATURE_DIM : BASE_FEATURE_DIM * 2]
    return float(np.mean(np.abs(velocity)))
