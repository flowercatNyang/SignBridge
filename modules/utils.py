class MockLandmarkList:
    """Mock class to simulate MediaPipe landmark list format."""
    def __init__(self, landmarks):
        self.landmark = landmarks

class MockResults:
    """Mock class to simulate MediaPipe results format."""
    def __init__(self, pose_results, hand_results):
        self.pose_landmarks = None
        self.right_hand_landmarks = None
        self.left_hand_landmarks = None
        if pose_results.pose_landmarks and len(pose_results.pose_landmarks) > 0:
            self.pose_landmarks = MockLandmarkList(pose_results.pose_landmarks[0])
        if hand_results.hand_landmarks and hand_results.handedness:
            for idx in range(len(hand_results.hand_landmarks)):
                hlm = hand_results.hand_landmarks[idx]
                handedness = hand_results.handedness[idx][0].category_name
                if handedness == "Right":
                    self.right_hand_landmarks = MockLandmarkList(hlm)
                elif handedness == "Left":
                    self.left_hand_landmarks = MockLandmarkList(hlm)
