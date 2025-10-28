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
PROJECT_ROOT="$(pwd)"
DATA_DIR="$PROJECT_ROOT/data"
GROUND_TRUTH_DIR="$DATA_DIR/classification-ground-truth"
LANGDATA_DIR="$DATA_DIR/langdata"
CLASSIFICATION_DIR="$DATA_DIR/classification"
MODEL_NAME="classification"

MODEL_OUTPUT_TRAINEDDATA="$CLASSIFICATION_DIR/$MODEL_NAME/$MODEL_NAME.traineddata"

BASE_MODEL="eng"
MAX_ITERATIONS=5000

# Location of base model data (MUST contain eng.traineddata and eng.lstm!)
TESSDATA_PATH="../classification_model/tessdata"
mkdir -p "$TESSDATA_PATH"
export TESSDATA_PREFIX="${TESSDATA_PATH%/}/"
BASE_TRAINEDDATA="$TESSDATA_PATH/$BASE_MODEL.traineddata"
BASE_LSTM="$TESSDATA_PATH/$BASE_MODEL.lstm"

msg "Using custom tessdata directory: $TESSDATA_PREFIX"

[ -f "$BASE_TRAINEDDATA" ] || err "Missing base traineddata: $BASE_TRAINEDDATA. Cannot continue."

case "$BASE_TRAINEDDATA" in
  *"Program Files"*) err "System tessdata path detected: $BASE_TRAINEDDATA" ;;
esac
case "$BASE_LSTM" in
  *"Program Files"*) err "System tessdata path detected: $BASE_LSTM" ;;
esac

# ================================================
# AUTO-EXTRACT LSTM IF MISSING
# ================================================
msg "Ensuring base LSTM exists in custom tessdata..."
if [ ! -f "$BASE_LSTM" ]; then
    msg "Base LSTM missing. Extracting from $BASE_TRAINEDDATA"
    combine_tessdata -e "$BASE_TRAINEDDATA" "$BASE_LSTM"
    [ -f "$BASE_LSTM" ] || err "Extraction failed. Cannot find $BASE_LSTM"
    ok "Extracted base LSTM to $BASE_LSTM"
else
    ok "Found existing base LSTM: $BASE_LSTM"
fi

msg "Verified base traineddata: $BASE_TRAINEDDATA"

# ================================================
# VALIDATE
# ================================================
msg "Checking training images..."
[ -d "$GROUND_TRUTH_DIR" ] || err "Folder missing: $GROUND_TRUTH_DIR"

count=$(find "$GROUND_TRUTH_DIR" -name "*.png" -o -name "*.jpg" -o -name "*.tif" | wc -l)
[ "$count" -gt 0 ] || err "No image files found in $GROUND_TRUTH_DIR"

ok "Found $count training images."

# ================================================
# GENERATE BOX & UNICHARSET
# ================================================
msg "Generating BOX files..."

for img in "$GROUND_TRUTH_DIR"/*.{png,jpg,tif,PNG,JPG,TIF}; do
    [ -f "$img" ] || continue
    base="${img%.*}"
    tesseract "$img" "$base" --psm 6 lstm.train >/dev/null 2>&1 || true
done

ok "BOX files generated."

msg "Extracting unicharset..."
unicharset_extractor "$GROUND_TRUTH_DIR"/*.box
mv unicharset "$CLASSIFICATION_DIR/unicharset"
ok "unicharset ready."

# ================================================
# COMBINE LANGUAGE MODEL
# ================================================
msg "Combining training language model..."
combine_lang_model \
  --input_unicharset "$CLASSIFICATION_DIR/unicharset" \
  --script_dir "$LANGDATA_DIR" \
  --output_dir "$CLASSIFICATION_DIR" \
  --lang "$MODEL_NAME"

ok "Language model created."

# ================================================
# CREATE LIST FILE
# ================================================
msg "Creating list.txt..."
find "$GROUND_TRUTH_DIR" -name "*.gt.txt" | sed 's/\.gt\.txt$//' > "$GROUND_TRUTH_DIR/list.txt"
ok "Training list ready."

# ================================================
# TRAIN MODEL
# ================================================
[ -f "$MODEL_OUTPUT_TRAINEDDATA" ] || err "Missing fine-tuning traineddata: $MODEL_OUTPUT_TRAINEDDATA"

msg "Starting LSTM Training with custom base model..."
msg "Continuing from: $BASE_LSTM"
msg "Using training configuration: $MODEL_OUTPUT_TRAINEDDATA"

mkdir -p "$CLASSIFICATION_DIR/checkpoints"

lstmtraining \
  --continue_from "$BASE_LSTM" \
  --traineddata "$MODEL_OUTPUT_TRAINEDDATA" \
  --train_listfile "$GROUND_TRUTH_DIR/list.txt" \
  --model_output "$CLASSIFICATION_DIR/checkpoints/$MODEL_NAME" \
  --max_iterations $MAX_ITERATIONS

ok "Training Complete."

# ================================================
# FINALIZE MODEL
# ================================================
msg "Finalizing model..."

lstmtraining \
  --stop_training \
  --continue_from "$CLASSIFICATION_DIR/checkpoints/${MODEL_NAME}" \
  --traineddata "$CLASSIFICATION_DIR/$MODEL_NAME/$MODEL_NAME.traineddata" \
  --model_output "$CLASSIFICATION_DIR/${MODEL_NAME}.traineddata"

ok "Final Model Saved: $CLASSIFICATION_DIR/${MODEL_NAME}.traineddata"

msg "Copying model to tessdata..."
cp "$CLASSIFICATION_DIR/${MODEL_NAME}.traineddata" "$TESSDATA_PATH/" || \
msg "Manual copy required → $CLASSIFICATION_DIR/${MODEL_NAME}.traineddata to $TESSDATA_PATH/"

ok "DONE ✅"
