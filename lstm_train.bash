#!/bin/bash

# ================================================
# 🧠 Fine-tuning Tesseract 5 untuk OCR Food Ingredients
# Target: Multiline & Multi-column text recognition
# Engine: LSTM (Tesseract 5.x)
# ================================================

set -e  # Exit on error

# ================================================
# Configuration Variables
# ================================================
PROJECT_ROOT="$(pwd)"
DATA_DIR="$PROJECT_ROOT/data"
GROUND_TRUTH_DIR="$DATA_DIR/classification-ground-truth"
LANGDATA_DIR="$DATA_DIR/langdata"
CLASSIFICATION_DIR="$DATA_DIR/classification"
MODEL_NAME="classification"
BASE_MODEL="eng"
MAX_ITERATIONS=5000

# Detect OS and set Tesseract path
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    TESSDATA_PATH="../classification_model/tessdata"
else
    TESSDATA_PATH="/usr/share/tesseract-ocr/5/tessdata"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ================================================
# Helper Functions
# ================================================
print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_dependencies() {
    print_header "Checking Dependencies"
    
    local deps=("tesseract" "unicharset_extractor" "combine_lang_model" "lstmtraining")
    local missing=0
    
    for dep in "${deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            print_success "$dep found"
        else
            print_error "$dep not found"
            missing=$((missing + 1))
        fi
    done
    
    if [ $missing -gt 0 ]; then
        print_error "Missing $missing dependencies. Please install Tesseract 5.x and training tools."
        exit 1
    fi
    
    print_success "All dependencies satisfied"
}

# ================================================
# Step 1: Validate Folder Structure
# ================================================
validate_structure() {
    print_header "[1] Validating Folder Structure"
    
    # Create directories if they don't exist
    mkdir -p "$GROUND_TRUTH_DIR"
    mkdir -p "$LANGDATA_DIR"
    mkdir -p "$CLASSIFICATION_DIR"
    
    # Check for training images
    local image_count=$(find "$GROUND_TRUTH_DIR" -name "*.png" -o -name "*.jpg" -o -name "*.tif" | wc -l)
    
    if [ $image_count -eq 0 ]; then
        print_error "No training images found in $GROUND_TRUTH_DIR"
        print_info "Please add .png/.jpg/.tif images with corresponding .gt.txt files"
        exit 1
    fi
    
    print_success "Found $image_count training images"
    
    # Validate image-ground truth pairs
    local unpaired=0
    shopt -s nullglob
    for img in "$GROUND_TRUTH_DIR"/*.png "$GROUND_TRUTH_DIR"/*.jpg "$GROUND_TRUTH_DIR"/*.tif; do
        [ -f "$img" ] || continue
        local base="${img%.*}"
        if [ ! -f "${base}.gt.txt" ]; then
            print_warning "Missing ground truth for: $(basename "$img")"
            unpaired=$((unpaired + 1))
        fi
    done
    shopt -u nullglob
    
    if [ $unpaired -gt 0 ]; then
        print_error "$unpaired images missing ground truth files (.gt.txt)"
        exit 1
    fi
    
    print_success "All images have corresponding ground truth files"
}

# ================================================
# Step 2: Extract BOX and UNICHARSET
# ================================================
extract_box_files() {
    print_header "[2] Extracting BOX Files and UNICHARSET"

    # Pastikan folder ground truth ada
    if [ ! -d "$GROUND_TRUTH_DIR" ]; then
        print_error "Folder GROUND_TRUTH_DIR tidak ditemukan: $GROUND_TRUTH_DIR"
        exit 1
    fi

    local processed=0
    shopt -s nullglob

    # Ambil semua gambar dari folder ground truth
    local image_files=("$GROUND_TRUTH_DIR"/*.png "$GROUND_TRUTH_DIR"/*.jpg "$GROUND_TRUTH_DIR"/*.tif \
                       "$GROUND_TRUTH_DIR"/*.PNG "$GROUND_TRUTH_DIR"/*.JPG "$GROUND_TRUTH_DIR"/*.TIF)

    if [ ${#image_files[@]} -eq 0 ]; then
        print_error "Tidak ada file gambar (.png/.jpg/.tif) ditemukan di $GROUND_TRUTH_DIR"
        exit 1
    fi

    # Loop setiap gambar
    for img in "${image_files[@]}"; do
        [ -f "$img" ] || continue

        local base="${img%.*}"
        print_info "Processing: $(basename "$img")"

        # Generate .box file
        tesseract "$img" "$base" --psm 6 lstm.train 2>&1 | grep -v "Warning" || true

        if [ -f "${base}.box" ]; then
            print_success "Generated: $(basename "${base}.box")"
            processed=$((processed + 1))
        else
            print_error "Failed to generate: $(basename "${base}.box")"
        fi
    done

    shopt -u nullglob

    if [ $processed -eq 0 ]; then
        print_error "Tidak ada BOX file yang berhasil dibuat"
        exit 1
    fi

    print_success "Processed $processed BOX files"

    # Extract unicharset
    print_info "Extracting unicharset from BOX files..."
    unicharset_extractor "$GROUND_TRUTH_DIR"/*.box

    if [ -f "$GROUND_TRUTH_DIR/unicharset" ]; then
        print_success "Unicharset extracted successfully → $GROUND_TRUTH_DIR/unicharset"
    elif [ -f "unicharset" ]; then
        print_success "Unicharset extracted successfully → $(pwd)/unicharset"
    else
        print_error "Failed to extract unicharset"
        exit 1
    fi
}


# ================================================
# Step 3: Create font_properties
# ================================================
create_font_properties() {
    print_header "[3] Creating font_properties"
    
    if [ ! -f "$LANGDATA_DIR/font_properties" ]; then
        echo "ClassificationFont 0 0 0 0 0" > "$LANGDATA_DIR/font_properties"
        print_success "Created font_properties"
    else
        print_info "font_properties already exists"
    fi
}

# ================================================
# Step 4: Prepare UNICHARSET
# ================================================
prepare_unicharset() {
    print_header "[4] Preparing Final UNICHARSET"
    
    if [ -f "unicharset" ]; then
        mv unicharset "$CLASSIFICATION_DIR/unicharset"
        print_success "Moved unicharset to $CLASSIFICATION_DIR/"
    else
        print_error "unicharset not found"
        exit 1
    fi
}

# ================================================
# Step 5: Combine Language Model
# ================================================
combine_language_model() {
    print_header "[5] Combining Language Model"
    
    print_info "Running combine_lang_model..."
    combine_lang_model \
        --input_unicharset "$CLASSIFICATION_DIR/unicharset" \
        --script_dir "$LANGDATA_DIR" \
        --output_dir "$CLASSIFICATION_DIR" \
        --lang "$MODEL_NAME"
    
    if [ -f "$CLASSIFICATION_DIR/$MODEL_NAME/$MODEL_NAME.traineddata" ]; then
        print_success "Language model combined successfully"
    else
        print_error "Failed to combine language model"
        exit 1
    fi
}

# ================================================
# Step 6: Create Training List File
# ================================================
create_training_list() {
    print_header "[6] Creating Training List File"
    
    local list_file="$GROUND_TRUTH_DIR/list.txt"
    > "$list_file"
    
   shopt -s nullglob
    local image_files=("$GROUND_TRUTH_DIR"/*.png "$GROUND_TRUTH_DIR"/*.jpg "$GROUND_TRUTH_DIR"/*.tif "$GROUND_TRUTH_DIR"/*.PNG "$GROUND_TRUTH_DIR"/*.JPG "$GROUND_TRUTH_DIR"/*.TIF)
    
    for img in "${image_files[@]}"; do
        [ -f "$img" ] || continue
        local base="${img%.*}"
        echo "$base" >> "$list_file"
    done
    
    shopt -u nullglob
    
    local line_count=$(wc -l < "$list_file")
    print_success "Created list.txt with $line_count entries"
}

# ================================================
# Step 7: LSTM Training (Fine-tuning)
# ================================================
train_model() {
    print_header "[7] Starting LSTM Training"
    
    print_info "Training parameters:"
    print_info "  Base model: $BASE_MODEL"
    print_info "  Max iterations: $MAX_ITERATIONS"
    print_info "  Output model: $MODEL_NAME"
    
    local base_traineddata="$TESSDATA_PATH/$BASE_MODEL.traineddata"
    
    if [ ! -f "$base_traineddata" ]; then
        print_error "Base model not found: $base_traineddata"
        exit 1
    fi
    
    print_info "Starting training... (this may take a while)"
    
    lstmtraining \
        --model_output "$CLASSIFICATION_DIR/checkpoints" \
        --continue_from "$base_traineddata" \
        --traineddata "$CLASSIFICATION_DIR/$MODEL_NAME/$MODEL_NAME.traineddata" \
        --train_listfile "$GROUND_TRUTH_DIR/list.txt" \
        --max_iterations "$MAX_ITERATIONS" \
        2>&1 | tee "$CLASSIFICATION_DIR/training.log"
    
    print_success "Training completed"
}

# ================================================
# Step 8: Finalize Model
# ================================================
finalize_model() {
    print_header "[8] Finalizing Model"
    
    print_info "Stopping training and creating final model..."
    
    lstmtraining \
        --stop_training \
        --continue_from "$CLASSIFICATION_DIR/checkpoints" \
        --traineddata "$CLASSIFICATION_DIR/$MODEL_NAME/$MODEL_NAME.traineddata" \
        --model_output "$CLASSIFICATION_DIR/$MODEL_NAME.traineddata"
    
    if [ -f "$CLASSIFICATION_DIR/$MODEL_NAME.traineddata" ]; then
        print_success "Final model created: $CLASSIFICATION_DIR/$MODEL_NAME.traineddata"
        
        # Copy to tessdata directory
        print_info "Copying model to tessdata directory..."
        cp "$CLASSIFICATION_DIR/$MODEL_NAME.traineddata" "$TESSDATA_PATH/" 2>/dev/null || {
            print_warning "Could not copy to tessdata. You may need to do this manually with sudo/admin rights"
            print_info "Copy command: cp $CLASSIFICATION_DIR/$MODEL_NAME.traineddata $TESSDATA_PATH/"
        }
    else
        print_error "Failed to create final model"
        exit 1
    fi
}

# ================================================
# Step 9: Test Model
# ================================================
test_model() {
    print_header "[9] Testing Model"
    
    # Find a test image
    local test_img=$(find "$GROUND_TRUTH_DIR" -name "*.png" -o -name "*.jpg" -o -name "*.tif" | head -n 1)
    
    if [ -z "$test_img" ]; then
        print_warning "No test image found. Skipping test."
        return
    fi
    
    print_info "Testing with: $(basename "$test_img")"
    
    local output_file="$CLASSIFICATION_DIR/test_output"
    
    tesseract "$test_img" "$output_file" \
        -l "$MODEL_NAME" \
        --tessdata-dir "$TESSDATA_PATH" \
        --oem 1 \
        --psm 6
    
    if [ -f "${output_file}.txt" ]; then
        print_success "OCR Test completed"
        print_info "Output saved to: ${output_file}.txt"
        echo ""
        print_info "OCR Result:"
        echo "----------------------------------------"
        cat "${output_file}.txt"
        echo "----------------------------------------"
    else
        print_warning "Test output not generated"
    fi
}

# ================================================
# Main Execution
# ================================================
main() {
    print_header "Tesseract 5 LSTM Fine-tuning Pipeline"
    print_info "Project: Food Ingredients OCR"
    print_info "Working directory: $PROJECT_ROOT"
    echo ""
    
    check_dependencies
    validate_structure
    extract_box_files
    create_font_properties
    prepare_unicharset
    combine_language_model
    create_training_list
    train_model
    finalize_model
    test_model
    
    print_header "Pipeline Completed Successfully!"
    print_success "Your trained model is ready: $CLASSIFICATION_DIR/$MODEL_NAME.traineddata"
    print_info "To use it: tesseract image.png output -l $MODEL_NAME --oem 1 --psm 6"
}

# Run the pipeline
main "$@"