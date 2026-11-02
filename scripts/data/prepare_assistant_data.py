"""Prepare the temporary demo vocabulary; no training or deployment is performed."""
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
os.environ["SIGNBRIDGE_VOCABULARY"] = "assistant_demo"

from scripts.data.prepare_five_word_data import main

if __name__ == "__main__":
    main()
