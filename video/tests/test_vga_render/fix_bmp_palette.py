import struct
import os

# Standard VGA 16-color palette
VGA_PALETTE = [
    (0, 0, 0),       # 0: Black
    (0, 0, 128),     # 1: Blue
    (0, 128, 0),     # 2: Green
    (0, 128, 128),   # 3: Cyan
    (128, 0, 0),     # 4: Red
    (128, 0, 128),   # 5: Magenta
    (128, 128, 0),   # 6: Brown
    (192, 192, 192), # 7: Light Gray
    (128, 128, 128), # 8: Dark Gray
    (0, 0, 255),     # 9: Light Blue
    (0, 255, 0),     # 10: Light Green
    (0, 255, 255),   # 11: Light Cyan
    (255, 0, 0),     # 12: Light Red
    (255, 0, 255),   # 13: Light Magenta
    (255, 255, 0),   # 14: Yellow
    (255, 255, 255)  # 15: White
]

def fix_bmp(path, out_path):
    print(f"Reading {path}...")
    with open(path, 'rb') as f:
        data = f.read()
    
    header = bytearray(data[:54])
    if header[:2] != b'BM':
        raise ValueError("Not a BMP file")
    
    offset = struct.unpack('<I', header[10:14])[0]
    bpp = struct.unpack('<H', header[28:30])[0]
    if bpp != 4:
        raise ValueError(f"Only 4bpp BMPs are supported, found {bpp}bpp")
    
    colors_used = struct.unpack('<I', header[46:50])[0]
    palette_size = colors_used if colors_used > 0 else 16
    
    orig_palette = []
    for i in range(palette_size):
        b, g, r, _ = data[54 + i*4 : 54 + (i+1)*4]
        orig_palette.append((r, g, b))
    
    # Map old palette indexes to new palette indexes based on color proximity
    lut = {}
    print("Mapping palette:")
    for i, (r, g, b) in enumerate(orig_palette):
        best_idx = 0
        min_dist = float('inf')
        for j, (vr, vg, vb) in enumerate(VGA_PALETTE):
            dist = (r - vr)**2 + (g - vg)**2 + (b - vb)**2
            if dist < min_dist:
                min_dist = dist
                best_idx = j
        lut[i] = best_idx
        print(f"  Old Index {i:2} (#{r:02X}{g:02X}{b:02X}) -> New Index {best_idx:2}")

    # Create new data with fixed palette and pixel data
    new_data = bytearray(data[:54])
    
    # Update palette in header area
    for r, g, b in VGA_PALETTE:
        new_data.extend([b, g, r, 0])
    
    # Ensure we respect the original pixel offset if it was larger than 54 + 16*4
    current_len = len(new_data)
    if current_len < offset:
        new_data.extend(data[current_len:offset])
    elif current_len > offset:
        print(f"Warning: New palette size ({current_len}) exceeds original offset ({offset}). This shouldn't happen for 4bpp.")

    # Update pixel data
    pixel_data = bytearray(data[offset:])
    print(f"Re-indexing {len(pixel_data)} bytes of pixel data...")
    for i in range(len(pixel_data)):
        byte = pixel_data[i]
        n1 = (byte >> 4) & 0x0F
        n2 = byte & 0x0F
        
        # Remap using LUT
        new_n1 = lut.get(n1, n1)
        new_n2 = lut.get(n2, n2)
        
        pixel_data[i] = (new_n1 << 4) | new_n2
    
    new_data.extend(pixel_data)
    
    print(f"Writing {out_path}...")
    with open(out_path, 'wb') as f:
        f.write(new_data)
    print("Done!")

if __name__ == '__main__':
    base_dir = '/Users/arielscarpinelli/mine/BondiXT/video/tests/test_mode12h_render/'
    fix_bmp(os.path.join(base_dir, 'win31.bmp'), os.path.join(base_dir, 'win31_fixed.bmp'))
