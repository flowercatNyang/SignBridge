"""Active five-word experiment; original 73-word maps remain in data/."""

# NUM_CLASSES = 73
WORDS = {
    "WORD1152": "아프다",
    "WORD2100": "위",
    "WORD2577": "아래",
    "WORD1592": "회사",
    "WORD1528": "엄마",
}
LABEL_MAP = {key: index for index, key in enumerate(WORDS)}
NUM_CLASSES = len(LABEL_MAP)
# EXPECTED_PER_CLASS = {"expert": 50, "team": 9}
EXPECTED_PER_CLASS = {"expert": 50, "team": 15}
