import collections

import numpy as np

from .features import SEQUENCE_LENGTH, build_temporal_features


class RecognitionGate:
    NO_SIGN = "NO_SIGN"
    TRANSITION = "TRANSITION"
    SIGN = "SIGN"

    def __init__(
        self,
        confidence_threshold=0.7,
        consensus_size=5,
        consensus_required=3,
        end_frames=5,
        motion_threshold=0.015,
        motion_frames=3,
    ):
        if not 0.0 <= confidence_threshold <= 1.0:
            raise ValueError("confidence_threshold must be between 0 and 1")
        if not 1 <= consensus_required <= consensus_size:
            raise ValueError("consensus_required must be between 1 and consensus_size")
        if end_frames < 1 or motion_frames < 1:
            raise ValueError("end_frames and motion_frames must be positive")
        self.confidence_threshold = confidence_threshold
        self.consensus_required = consensus_required
        self.end_frames = end_frames
        self.motion_threshold = motion_threshold
        self.motion_frames = motion_frames
        self.predictions = collections.deque(maxlen=consensus_size)
        self.reset()

    def reset(self):
        self.state = self.NO_SIGN
        self.features = collections.deque(maxlen=SEQUENCE_LENGTH)
        self.masks = collections.deque(maxlen=SEQUENCE_LENGTH)
        self.no_hand_count = 0
        self.motion_count = 0
        self.locked = False
        self.previous_frame = None
        self.predictions.clear()

    def add_frame(self, features, hand_mask):
        features = np.asarray(features, dtype=np.float32)
        hand_mask = np.asarray(hand_mask, dtype=np.float32)
        hand_present = bool(np.any(hand_mask > 0.5))
        frame_motion = (
            0.0
            if self.previous_frame is None
            else float(np.mean(np.abs(features - self.previous_frame)))
        )
        self.previous_frame = features

        if hand_present:
            self.no_hand_count = 0
        else:
            self.no_hand_count += 1
            if self.no_hand_count >= self.end_frames:
                self.reset()
                return None

        if self.state == self.NO_SIGN and hand_present:
            self.state = self.TRANSITION

        if self.locked:
            self.motion_count = self.motion_count + 1 if frame_motion >= self.motion_threshold else 0
            if self.motion_count < self.motion_frames:
                return None
            self.locked = False
            self.motion_count = 0
            self.features.clear()
            self.masks.clear()
            self.predictions.clear()
            self.state = self.TRANSITION

        if self.state != self.NO_SIGN:
            self.features.append(features)
            self.masks.append(hand_mask)
        if len(self.features) < SEQUENCE_LENGTH:
            return None

        self.state = self.SIGN
        return build_temporal_features(self.features, self.masks)

    def accept_probabilities(self, probabilities):
        confidence = float(np.max(probabilities))
        prediction = int(np.argmax(probabilities)) if confidence >= self.confidence_threshold else None
        self.predictions.append(prediction)
        if prediction is None:
            return None
        if sum(value == prediction for value in self.predictions) < self.consensus_required:
            return None
        self.locked = True
        self.predictions.clear()
        return prediction
