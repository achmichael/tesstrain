#!/bin/bash

# Folder berisi gambar dan box file
DATA_DIR="data/classification-ground-truth"
OUTPUT_DIR="data/classification-ground-truth"

echo "🚀 Memulai proses pembuatan file .lstmf ..."

# Loop semua file .png di folder
for f in "$DATA_DIR"/*.png; do
  [ -e "$f" ] || continue  # skip jika tidak ada file PNG

  base=$(basename "$f" .png)
  box_file="$OUTPUT_DIR/$base.box"

  echo "⏳ Memproses $f ..."

  # Cek apakah file .box ada
  if [ ! -f "$box_file" ]; then
    echo "⚙️  File .box tidak ditemukan, membuat dengan makebox..."
    tesseract "$f" "$OUTPUT_DIR/$base" --psm 6 makebox
  fi

  # Cek apakah file .box sudah berhasil dibuat
  if [ -f "$box_file" ]; then
    echo "📦 Membuat file .lstmf untuk $base ..."
    tesseract "$f" "$OUTPUT_DIR/$base" --psm 6 lstm.train
  else
    echo "❌ Gagal membuat .box untuk $base, dilewati..."
  fi
done

echo "✅ Semua file .lstmf telah dibuat."
