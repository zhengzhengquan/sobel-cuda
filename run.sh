# Used files
NEW_FILE="./images/sobel.new.pgm"
SOBEL_FILE="./images/sobel.default.pgm"
VALVE_FILE="./images/valve.pbm"

# Compile
make nvcc

# Run
./bin/run.out $VALVE_FILE $NEW_FILE

# Test
if [[ $(diff $NEW_FILE $SOBEL_FILE) ]]; then
    echo "Failure! $NEW_FILE and $SOBEL_FILE are DIFFERENT!"
else
    echo "Success! $NEW_FILE and $SOBEL_FILE are IDENTICAL!"
fi


