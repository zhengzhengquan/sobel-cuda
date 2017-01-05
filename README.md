## Description

This is an implementation of the Sobel operator, that is used in image processing and edge detection. More details - http://homepages.inf.ed.ac.uk/rbf/HIPR2/sobel.htm

## Compuling
To compile, run and test just execute ./run.sh

## Details
What the execution does:
1. compiles main.cu
2. runs the program on ./images/valve.pbm and writes to ./images/sobel.new.pgm
3. compares ./images/sobel.default.pgm to ./images/sobel.new.pgm to see if produced files are identical

After executing ./run.sh you can check ./images/sobel.new.pgm for yourself.



