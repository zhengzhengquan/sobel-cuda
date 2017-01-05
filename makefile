all:
	g++ -std=c++11 -fdiagnostics-color src/*.cpp -o bin/run.out

nvcc:
	nvcc src/*.cu -o bin/run.out

