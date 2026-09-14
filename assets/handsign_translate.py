import os
import time
import collections
import cv2
import numpy as np
import torch
import mediapipe as mp

from modules.features import extract_keypoints
from modules.utils import put_korean_text, load_models_and_maps, MockResults

BASE_DIR = os.path.dirname(os.path.abspath(__file__)) if "__file__" in locals() else os.getcwd()
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

def initialize_mediapipe():
    """Initializes Mediapipe Hand and Pose landmarkers."""
    BaseOptions = mp.tasks.BaseOptions
    VisionRunningMode = mp.tasks.vision.RunningMode

    HandLandmarker = mp.tasks.vision.HandLandmarker
    HandLandmarkerOptions = mp.tasks.vision.HandLandmarkerOptions
    hands = HandLandmarker.create_from_options(HandLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=os.path.join(BASE_DIR, 'hand_landmarker.task')),
        running_mode=VisionRunningMode.IMAGE,
        num_hands=2, min_hand_detection_confidence=0.5, min_hand_presence_confidence=0.5, min_tracking_confidence=0.5))
        
    PoseLandmarker = mp.tasks.vision.PoseLandmarker
    PoseLandmarkerOptions = mp.tasks.vision.PoseLandmarkerOptions
    pose = PoseLandmarker.create_from_options(PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=os.path.join(BASE_DIR, 'pose_landmarker_lite.task')),
        running_mode=VisionRunningMode.IMAGE,
        min_pose_detection_confidence=0.5, min_pose_presence_confidence=0.5, min_tracking_confidence=0.5))
        
    return hands, pose

def draw_landmarks(display_frame, results, w, h):
    """Draws hand and pose skeleton on the frame."""
    HAND_CONNECTIONS = [(0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8), 
                        (5, 9), (9, 10), (10, 11), (11, 12), (9, 13), (13, 14), (14, 15), (15, 16),
                        (13, 17), (17, 18), (18, 19), (19, 20), (0, 17)]
                        
    def draw_hand(hand_landmarks, conn_color, lm_color):
        if hand_landmarks:
            for connection in HAND_CONNECTIONS:
                p1 = hand_landmarks.landmark[connection[0]]
                p2 = hand_landmarks.landmark[connection[1]]
                x1, y1 = int((1 - p1.x) * w), int(p1.y * h)
                x2, y2 = int((1 - p2.x) * w), int(p2.y * h)
                cv2.line(display_frame, (x1, y1), (x2, y2), conn_color, 3)
            for lm in hand_landmarks.landmark:
                cv2.circle(display_frame, (int((1 - lm.x) * w), int(lm.y * h)), 4, lm_color, -1)

    draw_hand(results.right_hand_landmarks, (0, 255, 0), (0, 0, 255))
    draw_hand(results.left_hand_landmarks, (0, 0, 255), (0, 255, 0))

    if results.pose_landmarks:
        plm = results.pose_landmarks.landmark
        l_sh, r_sh = plm[11], plm[12]
        l_el, r_el = plm[13], plm[14]
        l_wr, r_wr = plm[15], plm[16]

        pts = {k: (int((1 - lm.x) * w), int(lm.y * h)) for k, lm in
               [('ls', l_sh), ('rs', r_sh), ('le', l_el), ('re', r_el), ('lw', l_wr), ('rw', r_wr)]}
        for a, b in [('ls', 'rs'), ('ls', 'le'), ('le', 'lw'), ('rs', 're'), ('re', 'rw')]:
            cv2.line(display_frame, pts[a], pts[b], (0, 255, 0), 4)
        for p in pts.values():
            cv2.circle(display_frame, p, 7, (0, 0, 255), -1)

def main():
    model, idx_to_label, categories, menu_number_map, all_menu_indices = load_models_and_maps(BASE_DIR, device)
    hands, pose = initialize_mediapipe()

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Error: Unable to access webcam.")
        return

    # App States
    APP_STATE = "MENU"
    CURRENT_CATEGORY = None
    CONFIRM_COUNT = 0
    LAST_PREDICTED_NUM = None

    sequence_buffer = collections.deque(maxlen=30)
    top3_predictions = [("Waiting...", 0.0)] * 3
    selected_sentence = []
    last_prediction_time = 0.0
    COOLDOWN_SECONDS = 1.0
    FRAME_SKIP = 2
    frame_count = 0

    while cap.isOpened():
        current_time = time.time()
        success, frame = cap.read()
        if not success: break
        
        frame_count += 1
        if frame_count % FRAME_SKIP != 0:
            display_frame = cv2.flip(frame, 1)
            cv2.imshow("SignBridge KSL Translator", display_frame)
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'): break
            continue

        h, w, _ = frame.shape
        image_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=image_rgb)
        
        hand_results = hands.detect(mp_image)
        pose_results = pose.detect(mp_image)
        results = MockResults(pose_results, hand_results)

        display_frame = cv2.flip(frame, 1)
        draw_landmarks(display_frame, results, w, h)

        frame_150d = extract_keypoints(results, w, h)
        sequence_buffer.append(frame_150d)
        is_cooldown = (current_time - last_prediction_time) < COOLDOWN_SECONDS

        if len(sequence_buffer) == 30 and not is_cooldown:
            seq_tensor = torch.tensor(np.array(sequence_buffer), dtype=torch.float32).unsqueeze(0).to(device)
            with torch.no_grad():
                logits = model(seq_tensor).squeeze(0)
                
                if APP_STATE == "MENU":
                    mask = torch.zeros_like(logits, dtype=torch.bool)
                    mask[all_menu_indices] = True
                    logits[~mask] = -9999.0
                    
                    probs = torch.softmax(logits, dim=0)
                    top1_prob, top1_idx = torch.max(probs, 0)
                    
                    if top1_prob.item() > 0.6: 
                        pred_word_id = top1_idx.item()
                        pred_num = next((num for num, idx in menu_number_map.items() if idx == pred_word_id), None)
                        
                        if pred_num is not None:
                            if pred_num == LAST_PREDICTED_NUM:
                                CONFIRM_COUNT += 1
                            else:
                                LAST_PREDICTED_NUM = pred_num
                                CONFIRM_COUNT = 1
                            
                            if CONFIRM_COUNT >= 3 and 1 <= int(pred_num) <= len(categories):
                                CURRENT_CATEGORY = categories[int(pred_num) - 1]
                                APP_STATE = "TRANSLATE"
                                CONFIRM_COUNT = 0
                                last_prediction_time = current_time
                                sequence_buffer.clear()
                                top3_predictions = [("Waiting...", 0.0)] * 3
                                selected_sentence.clear()
                    
                elif APP_STATE == "TRANSLATE":
                    mask = torch.zeros_like(logits, dtype=torch.bool)
                    cat_indices = CURRENT_CATEGORY["indices"]
                    if len(cat_indices) > 0:
                        mask[cat_indices] = True
                        logits[~mask] = -9999.0
                    
                    probs = torch.softmax(logits, dim=0)
                    top3_probs, top3_indices = torch.topk(probs, 3)
                    top3_predictions = [
                        (idx_to_label.get(top3_indices[i].item(), f"WORD{top3_indices[i].item():04d}"), top3_probs[i].item() * 100)
                        for i in range(3)
                    ]
                    last_prediction_time = current_time

        overlay = display_frame.copy()
        cv2.rectangle(overlay, (10, 10), (w - 10, 165), (30, 30, 30), -1)
        display_frame = cv2.addWeighted(overlay, 0.75, display_frame, 0.25, 0)
        
        if APP_STATE == "MENU":
            display_frame = put_korean_text(display_frame, "[Menu] Sign a number (1-7) to select category", (20, 20), 22, (0, 255, 255))
            
            for i, cat in enumerate(categories):
                col, row = i % 4, i // 4
                x, y = 20 + col * 150, 70 + row * 40
                text = f"[{cat['id']}] {cat['name'].split(' ')[1]}"
                color = (0, 255, 0) if str(LAST_PREDICTED_NUM) == str(cat['id']) else (255, 255, 255)
                display_frame = put_korean_text(display_frame, text, (x, y), 20, color)
                
            if LAST_PREDICTED_NUM is not None:
                display_frame = put_korean_text(display_frame, f"Recognized: {LAST_PREDICTED_NUM} ({CONFIRM_COUNT}/3)", (20, h - 50), 30, (0, 165, 255))
                
        elif APP_STATE == "TRANSLATE":
            status_str = f"Category: {CURRENT_CATEGORY['name']} (Press ESC to return to Menu)"
            display_frame = put_korean_text(display_frame, status_str, (20, 20), 40, (0, 255, 255))
            
            colors = [(0, 255, 0), (255, 200, 0), (0, 165, 255)]
            for i, (w_label, prob) in enumerate(top3_predictions):
                display_frame = put_korean_text(display_frame, f"[{i+1}] {w_label} ({prob:.1f}%)", (20 + i * 200, 70), 22, colors[i])
                
            sentence_str = " ".join(selected_sentence) if selected_sentence else "(Press 1, 2, 3 to assemble words)"
            display_frame = put_korean_text(display_frame, f"Assembled: {sentence_str}", (20, 120), 24, (255, 255, 255))
            
        cv2.imshow("SignBridge KSL Translator", display_frame)

        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            break
        elif key == 27:
            if APP_STATE == "TRANSLATE":
                APP_STATE = "MENU"
                LAST_PREDICTED_NUM = None
                CONFIRM_COUNT = 0
                selected_sentence.clear()
                sequence_buffer.clear()
                last_prediction_time = current_time
        elif key in [ord('1'), ord('2'), ord('3')] and APP_STATE == "TRANSLATE":
            idx = key - ord('1')
            if "Waiting" not in top3_predictions[idx][0]:
                selected_sentence.append(top3_predictions[idx][0])
                last_prediction_time = current_time
        elif key == ord('c'):
            selected_sentence.clear()

    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    main()
