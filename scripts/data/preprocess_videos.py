"""Preprocess videos with the shared MediaPipe pipeline."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from modules.preprocessing import main


if __name__ == "__main__":
    main()
