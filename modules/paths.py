"""Project paths shared by CLI entry points and the inference pipeline."""

from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = PROJECT_ROOT / "data"
MODEL_DIR = PROJECT_ROOT / "models"
REPORT_DIR = PROJECT_ROOT / "reports"
MEDIAPIPE_DIR = PROJECT_ROOT / "assets" / "mediapipe"
