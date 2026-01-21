default: test_vga_render.ppm

test_vga_render: test_vga_render.cpp ../../src/video.h
	g++ test_vga_render.cpp -o test_vga_render

test_vga_render.ppm: test_vga_render
	./test_vga_render