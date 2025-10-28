#!/bin/bash

set -e

# ================================================
# COLORS
# ================================================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

msg() { echo -e "${YELLOW}▶ $1${NC}"; }
ok() { echo -e "${GREEN}✓ $1${NC}"; }
err() { echo -e "${RED}✗ $1${NC}"; exit 1; }

# ================================================
# CONFIGURATION
# ================================================
MODEL_NAME="classification"
START_MODEL=""  # Empty = train from scratch, set to "eng" for fine-tuning
MAX_ITERATIONS=5000
PSM=6  # Page segmentation mode for single line text

# If you want to fine-tune from existing model:
START_MODEL="eng"
TESSDATA="../classification_model/tessdata"

msg "========================================="
msg "Tesseract LSTM Training"
msg "========================================="
msg "Model Name: $MODEL_NAME"
msg "Max Iterations: $MAX_ITERATIONS"
msg "PSM Mode: $PSM"

if [ -z "$START_MODEL" ]; then
    msg "Training Mode: FROM SCRATCH"
else
    msg "Training Mode: FINE-TUNING from $START_MODEL"
fi

# ================================================
# VALIDATE GROUND TRUTH
# ================================================
GROUND_TRUTH_DIR="data/${MODEL_NAME}-ground-truth"

msg "Checking ground truth directory: $GROUND_TRUTH_DIR"
[ -d "$GROUND_TRUTH_DIR" ] || err "Ground truth directory not found: $GROUND_TRUTH_DIR"

# Count ground truth files
gt_count=$(find "$GROUND_TRUTH_DIR" -name "*.gt.txt" | wc -l)
img_count=$(find "$GROUND_TRUTH_DIR" -name "*.png" -o -name "*.jpg" -o -name "*.tif" | wc -l)

msg "Found $gt_count ground truth files"
msg "Found $img_count image files"

[ "$gt_count" -gt 0 ] || err "No ground truth (.gt.txt) files found!"
[ "$img_count" -gt 0 ] || err "No image files found!"

ok "Ground truth validation passed"

# ================================================
# CLEAN OLD FILES
# ================================================
msg "Cleaning old training files..."
make clean MODEL_NAME="$MODEL_NAME" 2>/dev/null || true
ok "Cleaned"

# ================================================
# RUN TRAINING WITH MAKEFILE
# ================================================
msg "Starting training process..."
msg "This will:"
msg "  1. Extract unicharset"
msg "  2. Create proto model"
msg "  3. Generate LSTMF files"
msg "  4. Train the model"

if [ -z "$START_MODEL" ]; then
    # Train from scratch
    msg "Training from scratch..."
    make training MODEL_NAME="$MODEL_NAME" \
         MAX_ITERATIONS="$MAX_ITERATIONS" \
         PSM="$PSM" || err "Training failed!"
else
    # Fine-tune from existing model
    msg "Fine-tuning from $START_MODEL..."
    make training MODEL_NAME="$MODEL_NAME" \
         START_MODEL="$START_MODEL" \
         TESSDATA="$TESSDATA" \
         MAX_ITERATIONS="$MAX_ITERATIONS" \
         PSM="$PSM" || err "Training failed!"
fi

ok "Training completed successfully!"

# ================================================
# CREATE FINAL TRAINEDDATA
# ================================================
msg "Creating final traineddata file..."
make traineddata MODEL_NAME="$MODEL_NAME" || err "Failed to create traineddata"

ok "Final model created: data/${MODEL_NAME}.traineddata"

msg "========================================="
ok "TRAINING COMPLETE! ✅"
msg "========================================="
msg "Your trained model is ready:"
msg "  📦 data/${MODEL_NAME}.traineddata"
msg ""
msg "To use this model with Tesseract:"
msg "  1. Copy it to your tessdata directory"
msg "  2. Run: tesseract image.png output -l $MODEL_NAME"
msg "========================================="
