#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <algorithm>
#include "../../src/video.h"

// BMP Header structures (simplified)
#pragma pack(push, 1)
struct BMPHeader {
    uint16_t signature;
    uint32_t fileSize;
    uint32_t reserved;
    uint32_t dataOffset;
    uint32_t headerSize;
    int32_t  width;
    int32_t  height;
    uint16_t planes;
    uint16_t bitCount;
    uint32_t compression;
    uint32_t imageSize;
    int32_t  xPixelsPerMeter;
    int32_t  yPixelsPerMeter;
    uint32_t colorsUsed;
    uint32_t colorsImportant;
};
#pragma pack(pop)

void drawTestImageThruBus() {
    FILE *f = fopen("win31.bmp", "rb");
    if (!f) {
        printf("Error: Could not open win31.bmp\n");
        exit(1);
    }

    BMPHeader header;
    fread(&header, sizeof(header), 1, f);

    if (header.signature != 0x4D42) {
        printf("Error: Not a BMP file\n");
        exit(1);
    }

    if (header.bitCount != 4) {
        printf("Error: Only 4-bit BMP supported (got %d)\n", header.bitCount);
        exit(1);
    }

    if (header.width != 640 || abs(header.height) != 480) {
        printf("Error: Image must be 640x480 (got %dx%d)\n", header.width, header.height);
        exit(1);
    }

    // Seek to pixel data
    fseek(f, header.dataOffset, SEEK_SET);

    // Read pixel data
    // Rows are 4-byte alinged. 640 * 4 bits = 320 bytes. 
    // 320 is divisible by 4, so no padding handling needed for this resolution.
    int rowSize = (header.width + 1) / 2;
    std::vector<uint8_t> buffer(rowSize * abs(header.height));
    fread(buffer.data(), 1, buffer.size(), f);
    fclose(f);

    // Set video mode 12h
    processIO(0x3c2, 0xe3, true);

    // Process image
    // BMP is usually bottom-up
    bool bottomUp = (header.height > 0);
    int height = abs(header.height);

    for (int y = 0; y < height; y++) {
        int srcY = bottomUp ? (height - 1 - y) : y;
        const uint8_t* rowPtr = &buffer[srcY * rowSize];

        for (int byte_x = 0; byte_x < 80; byte_x++) {
            // Process 8 pixels (4 bytes in source) at a time to form one VGA byte
            // Pixels x to x+7
            
            // Collect the 8 pixels indices
            uint8_t pixels[8];
            for (int i = 0; i < 4; i++) {
                uint8_t b = rowPtr[byte_x * 4 + i];
                // High nibble is first pixel
                pixels[i*2]   = (b >> 4) & 0xF;
                pixels[i*2+1] = b & 0xF;
            }

            // Write to VGA memory
            // For each plane 0-3
            for (int plane = 0; plane < 4; plane++) {
                processIO(0x3CF, (1 << plane), true);
                
                uint8_t vga_byte = 0;
                for (int bit = 0; bit < 8; bit++) {
                    if (pixels[bit] & (1 << plane)) {
                        vga_byte |= (1 << (7 - bit));
                    }
                }
                
                // Address: 0xA0000 + y * 80 + byte_x
                uint32_t addr = 0xA0000 + y * 80 + byte_x;
                
                // Only write if not 0 (optimization, though real hardware would write 0s too)
                 // Actually we must write everything to ensure correct state if memory wasn't clear
                processMemoryBusMessage(addr, vga_byte, true);
            }
        }
    }
}

int main() {
    drawTestImageThruBus();
    
    FILE *f = fopen("test_vga_render.ppm", "w+");
    fprintf(f, "P3\n640 480 255\n");
    for (int y = 0; y < 480; y++) {
        for (int x = 0; x < 640; x++) {
            uint8_t color = vga_data_array[y * 640 + x];
            // Decode color from array (assuming it stores CGA_PALETTE16 values directly)
            // The video.h implementation stores the looked-up color in vga_data_array
            // So we need to decompose it back to R,G,B
            
            // CGA_PALETTE16 definition:
            // 00BBGGRR format (6-bit color)
            
            uint8_t r = color & 0b11;
            uint8_t g = (color >> 2) & 0b11;
            uint8_t b = (color >> 4) & 0b11;
            
            // Scale 2-bit color to 8-bit color (0-255)
            r = (r * 255) / 3;
            g = (g * 255) / 3;
            b = (b * 255) / 3;  
            fprintf(f, "%03d %03d %03d\t", r, g, b);
        }
        fprintf(f, "\n");
    }

    fclose(f);	
    return 0;
}
