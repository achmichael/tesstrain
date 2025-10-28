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

# Maximum lines per gt.txt file (1 for single-line training)
MAX_LINES=1

msg "Multi-line Image Splitter for Tesseract Training"
msg "================================================"
echo ""

# ================================================
# CHECK DEPENDENCIES
# ================================================
msg "Checking dependencies..."

if ! command -v convert &> /dev/null; then
    err "ImageMagick 'convert' command not found. Please install ImageMagick."
fi

if ! command -v python3 &> /dev/null; then
    err "Python3 not found. Please install Python3."
fi

ok "All dependencies found"
echo ""

# ================================================
# ANALYZE GROUND TRUTH FILES
# ================================================
msg "Analyzing ground truth files..."
echo ""

multiline_files=()
total_files=0

for gt_file in "$GROUND_TRUTH_DIR"/*.gt.txt; do
    [ -f "$gt_file" ] || continue
    
    total_files=$((total_files + 1))
    line_count=$(wc -l < "$gt_file")
    
    if [ "$line_count" -gt "$MAX_LINES" ]; then
        base_name=$(basename "$gt_file" .gt.txt)
        multiline_files+=("$base_name")
        info "Found multi-line: $base_name ($line_count lines)"
    fi
done

echo ""

if [ ${#multiline_files[@]} -eq 0 ]; then
    ok "All $total_files files are single-line. No splitting needed!"
    exit 0
fi

msg "Found ${#multiline_files[@]} multi-line file(s) out of $total_files total"
echo ""

# ================================================
# SPLIT IMAGES AND GROUND TRUTH
# ================================================
msg "Splitting multi-line images..."
echo ""

for base_name in "${multiline_files[@]}"; do
    gt_file="$GROUND_TRUTH_DIR/${base_name}.gt.txt"
    img_file="$GROUND_TRUTH_DIR/${base_name}.png"
    
    # Try different image extensions
    if [ ! -f "$img_file" ]; then
        img_file="$GROUND_TRUTH_DIR/${base_name}.jpg"
    fi
    if [ ! -f "$img_file" ]; then
        img_file="$GROUND_TRUTH_DIR/${base_name}.tif"
    fi
    
    if [ ! -f "$img_file" ]; then
        err "Image file not found for: $base_name"
        continue
    fi
    
    info "Processing: $base_name"
    
    # Get image dimensions
    img_height=$(identify -format "%h" "$img_file")
    img_width=$(identify -format "%w" "$img_file")
    line_count=$(wc -l < "$gt_file")
    
    info "  Image: ${img_width}x${img_height}, Lines: $line_count"
    
    # Calculate approximate height per line
    line_height=$((img_height / line_count))
    
    # Read lines into array
    mapfile -t lines < "$gt_file"
    
    # Split image and create new gt.txt files
    line_num=0
    for line in "${lines[@]}"; do
        # Skip empty lines
        [ -z "$line" ] && continue
        
        line_num=$((line_num + 1))
        
        # Calculate crop region
        y_start=$(( (line_num - 1) * line_height ))
        
        # New filename
        new_base="${base_name}_line$(printf "%03d" $line_num)"
        new_img="$GROUND_TRUTH_DIR/${new_base}.png"
        new_gt="$GROUND_TRUTH_DIR/${new_base}.gt.txt"
        
        # Crop image
        convert "$img_file" -crop "${img_width}x${line_height}+0+${y_start}" +repage "$new_img" 2>/dev/null
        
        # Create ground truth file
        echo "$line" > "$new_gt"
        
        info "    Created: ${new_base} ($(echo -n "$line" | wc -m) chars)"
    done
    
    # Move original files to backup
    backup_dir="$GROUND_TRUTH_DIR/multiline_originals"
    mkdir -p "$backup_dir"
    mv "$img_file" "$backup_dir/"
    mv "$gt_file" "$backup_dir/"
    
    ok "  Split into $line_num single-line images"
    echo ""
done

# ================================================
# SUMMARY
# ================================================
msg "=============================================="
msg "Summary"
msg "=============================================="
ok "Successfully split ${#multiline_files[@]} multi-line image(s)"
info "Original files moved to: $GROUND_TRUTH_DIR/multiline_originals"
echo ""

# Count new files
single_line_count=$(find "$GROUND_TRUTH_DIR" -maxdepth 1 -name "*.gt.txt" | wc -l)
ok "Total single-line training images: $single_line_count"
echo ""

msg "Next steps:"
info "1. Review the split images to ensure quality"
info "2. Manually adjust any incorrectly split images"
info "3. Run your training script: ./lstm_train.bash"
echo ""

ok "Done! ✅"
