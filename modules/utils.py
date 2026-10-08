import os
import json
import numpy as np
from PIL import ImageFont, ImageDraw, Image
import torch
from .models import SignLanguageModel

def put_korean_text(img, text, position, font_size, color):
    """
    Renders Korean text using Pillow and converts it back to an OpenCV image array.
    """
    img_pil = Image.fromarray(img)
    draw = ImageDraw.Draw(img_pil)
    try:
        font = ImageFont.truetype("malgun.ttf", font_size)
    except IOError:
        font = ImageFont.load_default()
    b, g, r = color
    draw.text(position, text, font=font, fill=(b, g, r))
    return np.array(img_pil)

def load_models_and_maps(base_dir, device):
    """
    Loads JSON maps and the PyTorch models for inference.
    """
    label_map_path = os.path.join(base_dir, "core_label_map.json") if os.path.exists(os.path.join(base_dir, "core_label_map.json")) else os.path.join(base_dir, "data", "processed", "core_label_map.json")
    category_map_path = os.path.join(base_dir, "core_category_map.json") if os.path.exists(os.path.join(base_dir, "core_category_map.json")) else os.path.join(base_dir, "data", "processed", "core_category_map.json")
    model_path = os.path.join(base_dir, "models", "sign_language_gru.pth") if os.path.exists(os.path.join(base_dir, "models", "sign_language_gru.pth")) else os.path.join(base_dir, "sign_language_gru.pth")
    dict_path = os.path.join(base_dir, "core_ksl_word_dictionary.json") if os.path.exists(os.path.join(base_dir, "core_ksl_word_dictionary.json")) else os.path.join(base_dir, "data", "processed", "core_ksl_word_dictionary.json")

    if os.path.exists(label_map_path):
        with open(label_map_path, "r", encoding="utf-8") as f:
            label_map = json.load(f)
    else:
        label_map = {f"WORD{i+1:04d}": i for i in range(114)}

    korean_dict = {}
    if os.path.exists(dict_path):
        with open(dict_path, "r", encoding="utf-8") as f:
            korean_dict = json.load(f)

    idx_to_label = {class_idx: korean_dict.get(word_key, word_key) for word_key, class_idx in label_map.items()}
    
    with open(category_map_path, "r", encoding="utf-8") as f:
        cat_map_data = json.load(f)
    
    categories = cat_map_data["categories"]
    menu_number_map = {int(k): v for k, v in cat_map_data["menu_number_map"].items()}
    all_menu_indices = cat_map_data["all_menu_indices"]

    model = SignLanguageModel(num_classes=len(label_map), input_dim=150, hidden_dim=64, num_layers=2).to(device)
    
    if os.path.exists(model_path):
        state = torch.load(model_path, map_location=device)
        model.load_state_dict(state)
    
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
