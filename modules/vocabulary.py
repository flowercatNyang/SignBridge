"""Select a training vocabulary without relabeling existing five-word assets."""

import os

# NUM_CLASSES = 73
WORDS = {
    "WORD1152": "아프다",
    "WORD2100": "위",
    "WORD2577": "아래",
    "WORD1592": "회사",
    "WORD1528": "엄마",
}
# EXPECTED_PER_CLASS = {"expert": 50, "team": 9}
EXPECTED_PER_CLASS = {"expert": 50, "team": 15}

PROFILE = os.getenv("SIGNBRIDGE_VOCABULARY", "five")
if PROFILE in {"assistant_demo", "assistant23"}:
    WORDS = {
        **WORDS,
        "WORD1157": "나",
        "WORD0948": "가깝다",
        "WORD0932": "매일매일",
        "WORD1273": "일어나다",
        "WORD2639": "팔",  # Numeric 8, not the body part WORD1147.
        "WORD2268": "그렇다",
        "WORD1359": "틀리다",
        "WORD2576": "상부",  # Direction up; WORD2100 is the stomach.
        # Temporarily excluded from the demo; restore when expanding the dataset.
        # "WORD1295": "걷다",
        # "WORD1370": "귀",
        # "WORD2631": "영",
        # "WORD2632": "일",
        # "WORD2633": "이",
        # "WORD2634": "삼",
        # "WORD2635": "사",
        # "WORD2636": "오",
        # "WORD2637": "육",
        # "WORD2638": "칠",
        # "WORD2640": "구",
    }
    # Three clips/class is the starting minimum, not a claim of generalization.
    EXPECTED_PER_CLASS = {"expert": 50, "team": 3}
elif PROFILE != "five":
    raise ValueError("SIGNBRIDGE_VOCABULARY must be five or assistant_demo (assistant23 is a legacy alias)")

LABEL_MAP = {key: index for index, key in enumerate(WORDS)}
NUM_CLASSES = len(WORDS)
PROCESSED_NAME = "processed_five" if PROFILE == "five" else "processed_assistant_demo"

# Keep dictionary labels canonical in checkpoints; disambiguate UI/LLM input.
DISPLAY_LABELS = {
    "WORD2100": "위(내장)",
    "WORD2576": "위(방향)",
    **{f"WORD{2631 + digit:04d}": str(digit) for digit in range(10)},
}
