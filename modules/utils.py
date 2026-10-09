import os
import json
import numpy as np
from PIL import ImageFont, ImageDraw, Image
import torch
from .models import SignLanguageModel
from .vocabulary import LABEL_MAP, NUM_CLASSES, WORDS

def put_korean_text(img, text, position, font_size, color):
    """
    Renders Korean text using Pillow and converts it back to an OpenCV image array.
    """
    img_pil = Image.fromarray(img)
    draw = ImageDraw.Draw(img_pil)
    try:
        font = ImageFont.truetype("malgun.ttf", font_size)
    except IOError:
        # font = ImageFont.load_default()
        font = None
        for candidate in ("/System/Library/Fonts/AppleSDGothicNeo.ttc",
                          "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"):
            if os.path.exists(candidate):
                font = ImageFont.truetype(candidate, font_size)
                break
        if font is None:
            font = ImageFont.load_default()
    b, g, r = color
    draw.text(position, text, font=font, fill=(b, g, r))
    return np.array(img_pil)

def load_models_and_maps(base_dir, device, checkpoint_path=None):
    """
    Loads JSON maps and the PyTorch models for inference.
    """
    label_map_path = os.path.join(base_dir, "core_label_map.json") if os.path.exists(os.path.join(base_dir, "core_label_map.json")) else os.path.join(base_dir, "data", "processed", "core_label_map.json")
    category_map_path = os.path.join(base_dir, "core_category_map.json") if os.path.exists(os.path.join(base_dir, "core_category_map.json")) else os.path.join(base_dir, "data", "processed", "core_category_map.json")
    # model_path = checkpoint_path or os.path.join(base_dir, "models", "sign_language_gru.pth")
    model_path = checkpoint_path or os.path.join(base_dir, "models", "sign_language_five_words.pth")
    dict_path = os.path.join(base_dir, "core_ksl_word_dictionary.json") if os.path.exists(os.path.join(base_dir, "core_ksl_word_dictionary.json")) else os.path.join(base_dir, "data", "processed", "core_ksl_word_dictionary.json")

    # if os.path.exists(label_map_path):
    #     with open(label_map_path, "r", encoding="utf-8") as f:
    #         label_map = json.load(f)
    # else:
    #     raise FileNotFoundError(f"Label map not found: {label_map_path}")
    # if len(label_map) != 73:
    #     raise ValueError(f"Expected 73 classes, found {len(label_map)}")
    label_map = LABEL_MAP

    korean_dict = dict(WORDS)
    if os.path.exists(dict_path):
        with open(dict_path, "r", encoding="utf-8") as f:
            korean_dict = json.load(f)

    idx_to_label = {class_idx: korean_dict.get(word_key, word_key) for word_key, class_idx in label_map.items()}
    
    # with open(category_map_path, "r", encoding="utf-8") as f:
    #     cat_map_data = json.load(f)
    
    # categories = cat_map_data["categories"]
    # menu_number_map = {int(k): v for k, v in cat_map_data["menu_number_map"].items()}
    # all_menu_indices = cat_map_data["all_menu_indices"]
    categories = [{"id": 1, "name": "아프다 · 위 · 아래 · 회사 · 엄마", "indices": list(range(NUM_CLASSES))}]
    menu_number_map = {}
    all_menu_indices = list(range(NUM_CLASSES))

    if not os.path.exists(model_path):
        raise FileNotFoundError(
            f"Checkpoint not found: {model_path}. Run train_pipeline.py or pass --checkpoint."
        )
    checkpoint = torch.load(model_path, map_location=device)
    if checkpoint.get("format_version") != 2:
        raise ValueError(
            "Legacy 150D checkpoints are incompatible with the 452D feature pipeline."
        )
    model = SignLanguageModel(**checkpoint["model_config"]).to(device)
    if model.config["num_classes"] != NUM_CLASSES or checkpoint.get("label_map") != LABEL_MAP:
        raise ValueError("Checkpoint vocabulary does not match the active five-word experiment")
    model.load_state_dict(checkpoint["model_state"])
    
    model.eval()
    
    return model, idx_to_label, categories, menu_number_map, all_menu_indices

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
