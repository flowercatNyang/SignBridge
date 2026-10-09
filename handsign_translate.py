import argparse
import os
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
import torch

from modules.features import extract_keypoints
from modules.preprocessing import create_landmarkers
from modules.realtime import RecognitionGate
from modules.utils import MockResults, load_models_and_maps, put_korean_text


BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def draw_landmarks(display_frame, results, width, height):
    hand_connections = [
        (0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8),
        (5, 9), (9, 10), (10, 11), (11, 12), (9, 13), (13, 14), (14, 15),
        (15, 16), (13, 17), (17, 18), (18, 19), (19, 20), (0, 17),
    ]

    def draw_hand(hand_landmarks, connection_color, landmark_color):
        if not hand_landmarks:
            return
        for start, end in hand_connections:
            point1, point2 = hand_landmarks.landmark[start], hand_landmarks.landmark[end]
            xy1 = (int((1 - point1.x) * width), int(point1.y * height))
            xy2 = (int((1 - point2.x) * width), int(point2.y * height))
            cv2.line(display_frame, xy1, xy2, connection_color, 3)
        for landmark in hand_landmarks.landmark:
            point = (int((1 - landmark.x) * width), int(landmark.y * height))
            cv2.circle(display_frame, point, 4, landmark_color, -1)

    draw_hand(results.right_hand_landmarks, (0, 255, 0), (0, 0, 255))
    draw_hand(results.left_hand_landmarks, (0, 0, 255), (0, 255, 0))

    if results.pose_landmarks:
        landmarks = results.pose_landmarks.landmark
        points = {
            "ls": landmarks[11],
            "rs": landmarks[12],
            "le": landmarks[13],
            "re": landmarks[14],
            "lw": landmarks[15],
            "rw": landmarks[16],
        }
        points = {
            name: (int((1 - point.x) * width), int(point.y * height))
            for name, point in points.items()
        }
        for start, end in (("ls", "rs"), ("ls", "le"), ("le", "lw"), ("rs", "re"), ("re", "rw")):
            cv2.line(display_frame, points[start], points[end], (0, 255, 0), 4)
        for point in points.values():
            cv2.circle(display_frame, point, 7, (0, 0, 255), -1)


def masked_probabilities(logits, allowed_indices):
    if allowed_indices:
        mask = torch.zeros_like(logits, dtype=torch.bool)
        mask[allowed_indices] = True
        logits = logits.masked_fill(~mask, -torch.inf)
    return torch.softmax(logits, dim=0)


def main():
    parser = argparse.ArgumentParser(description="Real-time KSL recognition")
    parser.add_argument(
        "--checkpoint",
        default=os.path.join(BASE_DIR, "models", "sign_language_gru.pth"),
    )
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--confidence", type=float, default=0.7)
    parser.add_argument("--consensus-size", type=int, default=5)
    parser.add_argument("--consensus-required", type=int, default=3)
    parser.add_argument("--frame-skip", type=int, default=2)
    args = parser.parse_args()

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model, idx_to_label, categories, menu_number_map, all_menu_indices = (
        load_models_and_maps(BASE_DIR, device, args.checkpoint)
    )
    hands, pose = create_landmarkers(Path(BASE_DIR))
    gate = RecognitionGate(
        confidence_threshold=args.confidence,
        consensus_size=args.consensus_size,
        consensus_required=args.consensus_required,
    )

    capture = cv2.VideoCapture(args.camera)
    if not capture.isOpened():
        print("Error: Unable to access webcam.")
        return

    app_state = "MENU"
    current_category = None
    top3_predictions = [("Waiting...", 0.0)] * 3
    confirmed_word = None
    selected_sentence = []
    frame_count = 0
    last_results = None

    try:
        while capture.isOpened():
            success, frame = capture.read()
            if not success:
                break
            frame_count += 1
            height, width = frame.shape[:2]
            display_frame = cv2.flip(frame, 1)

            if frame_count % args.frame_skip == 0:
                image = mp.Image(
                    image_format=mp.ImageFormat.SRGB,
                    data=cv2.cvtColor(frame, cv2.COLOR_BGR2RGB),
                )
                last_results = MockResults(pose.detect(image), hands.detect(image))
                features, hand_mask = extract_keypoints(
                    last_results, width, height, return_mask=True
                )
                sequence = gate.add_frame(features, hand_mask)

                if sequence is not None:
                    inputs = torch.from_numpy(sequence).unsqueeze(0).to(device)
                    with torch.no_grad():
                        logits = model(inputs).squeeze(0)
                    allowed = (
                        all_menu_indices
                        if app_state == "MENU"
                        else current_category["indices"]
                    )
                    probabilities = masked_probabilities(logits, allowed)
                    top_count = min(3, len(allowed))
                    values, indices = torch.topk(probabilities, top_count)
                    top3_predictions = [
                        (
                            idx_to_label.get(int(index), f"WORD{int(index):04d}"),
                            float(value) * 100.0,
                        )
                        for value, index in zip(values.cpu(), indices.cpu())
                    ]
                    accepted = gate.accept_probabilities(probabilities.cpu().numpy())
                    if accepted is not None and app_state == "MENU":
                        number = next(
                            (number for number, index in menu_number_map.items() if index == accepted),
                            None,
                        )
                        if number is not None and 1 <= int(number) <= len(categories):
                            current_category = categories[int(number) - 1]
                            app_state = "TRANSLATE"
                            confirmed_word = None
                            top3_predictions = [("Waiting...", 0.0)] * 3
                            gate.reset()
                    elif accepted is not None:
                        confirmed_word = idx_to_label.get(accepted, f"WORD{accepted:04d}")

            if last_results is not None:
                draw_landmarks(display_frame, last_results, width, height)

            overlay = display_frame.copy()
            cv2.rectangle(overlay, (10, 10), (width - 10, 175), (30, 30, 30), -1)
            display_frame = cv2.addWeighted(overlay, 0.75, display_frame, 0.25, 0)
            state_text = f"Recognition: {gate.state}"
            display_frame = put_korean_text(
                display_frame, state_text, (20, 140), 20, (180, 180, 180)
            )

            if app_state == "MENU":
                display_frame = put_korean_text(
                    display_frame,
                    "[Menu] Sign a number (1-7) to select category",
                    (20, 20),
                    22,
                    (0, 255, 255),
                )
                for index, category in enumerate(categories):
                    column, row = index % 4, index // 4
                    text = f"[{category['id']}] {category['name'].split(' ')[-1]}"
                    display_frame = put_korean_text(
                        display_frame,
                        text,
                        (20 + column * 150, 70 + row * 40),
                        20,
                        (255, 255, 255),
                    )
            else:
                status = f"Category: {current_category['name']} (ESC: Menu)"
                display_frame = put_korean_text(
                    display_frame, status, (20, 20), 34, (0, 255, 255)
                )
                colors = [(0, 255, 0), (255, 200, 0), (0, 165, 255)]
                for index, (label, probability) in enumerate(top3_predictions):
                    display_frame = put_korean_text(
                        display_frame,
                        f"[{index + 1}] {label} ({probability:.1f}%)",
                        (20 + index * 200, 70),
                        22,
                        colors[index],
                    )
                confirmed = confirmed_word or "Waiting for consensus"
                display_frame = put_korean_text(
                    display_frame, f"Confirmed: {confirmed}", (20, 110), 22, (0, 255, 0)
                )
                sentence = " ".join(selected_sentence) or "(Press 1, 2, 3 to assemble words)"
                display_frame = put_korean_text(
                    display_frame, f"Assembled: {sentence}", (20, 150), 20, (255, 255, 255)
                )

            cv2.imshow("SignBridge KSL Translator", display_frame)
            key = cv2.waitKey(1) & 0xFF
            if key == ord("q"):
                break
            if key == 27 and app_state == "TRANSLATE":
                app_state = "MENU"
                current_category = None
                confirmed_word = None
                selected_sentence.clear()
                gate.reset()
            elif key in (ord("1"), ord("2"), ord("3")) and app_state == "TRANSLATE":
                index = key - ord("1")
                if index < len(top3_predictions) and "Waiting" not in top3_predictions[index][0]:
                    selected_sentence.append(top3_predictions[index][0])
            elif key == ord("c"):
                selected_sentence.clear()
    finally:
        capture.release()
        hands.close()
        pose.close()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
