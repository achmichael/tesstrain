#!/bin/bash

set -e

# ================================================
# COLORS
# ================================================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

msg() { echo -e "${YELLOW}▶ $1${NC}"; }
ok() { echo -e "${GREEN}✓ $1${NC}"; }
err() { echo -e "${RED}✗ $1${NC}"; exit 1; }
info() { echo -e "${BLUE}ℹ $1${NC}"; }

# ================================================
# CONFIGURATION
# ================================================
PROJECT_ROOT="$(pwd)"
DATA_DIR="$PROJECT_ROOT/data"
GROUND_TRUTH_DIR="$DATA_DIR/classification-ground-truth"

# Tesseract configuration
TESSDATA_PATH="../classification_model/tessdata"
export TESSDATA_PREFIX="${TESSDATA_PATH%/}/"

# OCR language to use (change this if needed)
OCR_LANG="eng"

# PSM (Page Segmentation Mode):
# 3  = Fully automatic page segmentation, but no OSD (default)
# 4  = Assume a single column of text of variable sizes
# 6  = Assume a single uniform block of text
# 11 = Sparse text. Find as much text as possible in no particular order
# 13 = Raw line. Treat the image as a single text line
PSM_MODE=6

# Backup existing gt.txt files?
BACKUP_EXISTING=true

msg "Ground Truth Generator for Tesseract Training"
msg "=============================================="
echo ""

# ================================================
# VALIDATE
# ================================================
msg "Validating configuration..."

[ -d "$GROUND_TRUTH_DIR" ] || err "Directory not found: $GROUND_TRUTH_DIR"

# Count images
image_count=$(find "$GROUND_TRUTH_DIR" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.tif" -o -name "*.PNG" -o -name "*.JPG" -o -name "*.TIF" \) | wc -l)

if [ "$image_count" -eq 0 ]; then
    err "No images found in $GROUND_TRUTH_DIR"
fi

ok "Found $image_count image(s) to process"
info "Using OCR language: $OCR_LANG"
info "Using PSM mode: $PSM_MODE"
echo ""

# ================================================
# BACKUP EXISTING FILES
# ================================================
if [ "$BACKUP_EXISTING" = true ]; then
    backup_count=$(find "$GROUND_TRUTH_DIR" -name "*.gt.txt" | wc -l)
    
    if [ "$backup_count" -gt 0 ]; then
        msg "Backing up existing ground truth files..."
        backup_dir="$GROUND_TRUTH_DIR/backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        
        find "$GROUND_TRUTH_DIR" -maxdepth 1 -name "*.gt.txt" -exec mv {} "$backup_dir/" \;
        ok "Backed up $backup_count file(s) to: $backup_dir"
        echo ""
    fi
fi

# ================================================
# PROCESS IMAGES
# ================================================
msg "Processing images and generating ground truth files..."
echo ""

processed=0
failed=0

for img_path in "$GROUND_TRUTH_DIR"/*.{png,jpg,tif,PNG,JPG,TIF}; do
    # Skip if file doesn't exist (for case when extension doesn't match)
    [ -f "$img_path" ] || continue
    
    # Get base filename without extension
    base_name="${img_path%.*}"
    img_filename=$(basename "$img_path")
    gt_file="${base_name}.gt.txt"
    
    info "Processing: $img_filename"
    
    # Check image dimensions
    if command -v identify &> /dev/null; then
        dimensions=$(identify -format "%wx%h" "$img_path" 2>/dev/null)
        info "  Image size: $dimensions"
    fi
    
    # Run Tesseract OCR
    if tesseract "$img_path" stdout --psm $PSM_MODE -l $OCR_LANG 2>/dev/null > "$gt_file"; then
        # Clean up the output (remove trailing newlines, extra spaces)
        # Keep all lines but trim whitespace
        if [ -f "$gt_file" ]; then
            # Remove trailing whitespace and empty lines at the end
            sed -i 's/[[:space:]]*$//' "$gt_file"
            sed -i -e :a -e '/^\s*$/d;N;ba' "$gt_file"
            
            # Get line count and character count
            line_count=$(wc -l < "$gt_file")
            char_count=$(wc -m < "$gt_file")
            
            # Add a single newline at the end if file is not empty
            if [ -s "$gt_file" ]; then
                # Ensure file ends with exactly one newline
                sed -i -e '$a\' "$gt_file"
                line_count=$((line_count + 1))
            fi
            
            ok "  Created: $(basename "$gt_file") ($line_count lines, $char_count chars)"
            
            # Show preview of first 100 characters
            preview=$(head -c 100 "$gt_file")
            info "  Preview: ${preview}..."
            
            processed=$((processed + 1))
        else
            err "  Failed to create ground truth file"
            failed=$((failed + 1))
        fi
    else
        err "  OCR failed for $img_filename"
        failed=$((failed + 1))
    fi
    
    echo ""
done

# ================================================
# SUMMARY
# ================================================
echo ""
msg "=============================================="
msg "Summary"
msg "=============================================="
ok "Successfully processed: $processed image(s)"

if [ "$failed" -gt 0 ]; then
    err "Failed: $failed image(s)"
else
    ok "No failures!"
fi

echo ""
msg "Ground truth files have been generated in:"
info "$GROUND_TRUTH_DIR"
echo ""
msg "Next steps:"
info "1. Review and manually correct the generated .gt.txt files"
info "2. Ensure each .gt.txt matches its corresponding image"
info "3. For multi-line images, consider splitting into single-line images"
info "4. Run your training script: ./lstm_train.bash"
echo ""

ok "Done! ✅"
