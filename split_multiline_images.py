#!/usr/bin/env python3
"""
Split multi-line images into single-line images for Tesseract training.
"""

import os
import sys
from pathlib import Path
from PIL import Image
import shutil

# Colors for terminal output
YELLOW = '\033[1;33m'
GREEN = '\033[0;32m'
RED = '\033[0;31m'
BLUE = '\033[0;34m'
NC = '\033[0m'

def msg(text): print(f"{YELLOW}▶ {text}{NC}")
def ok(text): print(f"{GREEN}✓ {text}{NC}")
def err(text): print(f"{RED}✗ {text}{NC}", file=sys.stderr)
def info(text): print(f"{BLUE}ℹ {text}{NC}")

# Configuration
PROJECT_ROOT = Path.cwd()
DATA_DIR = PROJECT_ROOT / "data"
GROUND_TRUTH_DIR = DATA_DIR / "classification-ground-truth"
MAX_LINES = 1

def main():
    msg("Multi-line Image Splitter for Tesseract Training")
    msg("=" * 50)
    print()
    
    if not GROUND_TRUTH_DIR.exists():
        err(f"Directory not found: {GROUND_TRUTH_DIR}")
        sys.exit(1)
    
    # Analyze ground truth files
    msg("Analyzing ground truth files...")
    print()
    
    multiline_files = []
    total_files = 0
    
    for gt_file in GROUND_TRUTH_DIR.glob("*.gt.txt"):
        total_files += 1
        
        with open(gt_file, 'r', encoding='utf-8') as f:
            lines = [line.strip() for line in f if line.strip()]
        
        line_count = len(lines)
        
        if line_count > MAX_LINES:
            base_name = gt_file.stem.replace('.gt', '')
            multiline_files.append((base_name, lines))
            info(f"Found multi-line: {base_name} ({line_count} lines)")
    
    print()
    
    if not multiline_files:
        ok(f"All {total_files} files are single-line. No splitting needed!")
        return
    
    msg(f"Found {len(multiline_files)} multi-line file(s) out of {total_files} total")
    print()
    
    # Split images and ground truth
    msg("Splitting multi-line images...")
    print()
    
    backup_dir = GROUND_TRUTH_DIR / "multiline_originals"
    backup_dir.mkdir(exist_ok=True)
    
    total_split = 0
    
    for base_name, lines in multiline_files:
        # Find image file
        img_file = None
        for ext in ['.png', '.jpg', '.jpeg', '.tif', '.tiff', '.PNG', '.JPG', '.JPEG']:
            candidate = GROUND_TRUTH_DIR / f"{base_name}{ext}"
            if candidate.exists():
                img_file = candidate
                break
        
        if not img_file:
            err(f"Image file not found for: {base_name}")
            continue
        
        gt_file = GROUND_TRUTH_DIR / f"{base_name}.gt.txt"
        
        info(f"Processing: {base_name}")
        
        try:
            # Load image
            img = Image.open(img_file)
            img_width, img_height = img.size
            line_count = len(lines)
            
            info(f"  Image: {img_width}x{img_height}, Lines: {line_count}")
            
            # Calculate approximate height per line
            line_height = img_height // line_count
            
            # Split image and create new gt.txt files
            for line_num, line_text in enumerate(lines, 1):
                if not line_text:
                    continue
                
                # Calculate crop region
                y_start = (line_num - 1) * line_height
                y_end = line_num * line_height if line_num < line_count else img_height
                
                # New filename
                new_base = f"{base_name}_line{line_num:03d}"
                new_img = GROUND_TRUTH_DIR / f"{new_base}.png"
                new_gt = GROUND_TRUTH_DIR / f"{new_base}.gt.txt"
                
                # Crop image
                cropped = img.crop((0, y_start, img_width, y_end))
                cropped.save(new_img)
                
                # Create ground truth file
                with open(new_gt, 'w', encoding='utf-8') as f:
                    f.write(line_text + '\n')
                
                info(f"    Created: {new_base} ({len(line_text)} chars)")
                total_split += 1
            
            # Move original files to backup
            shutil.move(str(img_file), str(backup_dir / img_file.name))
            shutil.move(str(gt_file), str(backup_dir / gt_file.name))
            
            ok(f"  Split into {line_count} single-line images")
            print()
            
        except Exception as e:
            err(f"Failed to process {base_name}: {e}")
            continue
    
    # Summary
    msg("=" * 50)
    msg("Summary")
    msg("=" * 50)
    ok(f"Successfully split {len(multiline_files)} multi-line image(s)")
    info(f"Original files moved to: {backup_dir}")
    print()
    
    # Count new files
    single_line_count = len(list(GROUND_TRUTH_DIR.glob("*.gt.txt")))
    ok(f"Total single-line training images: {single_line_count}")
    print()
    
    msg("Next steps:")
    info("1. Review the split images to ensure quality")
    info("2. Manually adjust any incorrectly split images")
    info("3. Run your training script: ./lstm_train.bash")
    print()
    
    ok("Done! ✅")

if __name__ == "__main__":
    main()
