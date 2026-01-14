default: test_cga_render.ppm

test_cga_render: test_cga_render.cpp ../../src/video.h
	g++ test_cga_render.cpp -o test_cga_render

test_cga_render.ppm: test_cga_render
	./test_cga_render