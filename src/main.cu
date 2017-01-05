#include <stdio.h>
#include <assert.h>

#define CHECK(e) { int res = (e); if (res) printf("CUDA ERROR %d\n", res); }

// Used for debugging so that the output is all white
// #define THRESH -1

#define THRESH 10000

#define WARP_SIZE 32

// Both the x and y dimention of blocks as they are square
#define BLOCK_DIM 16

texture<unsigned char, 2> imageTex;

struct Image {
    int width;
    int height;
    unsigned char *img;
    unsigned char *dev_img;
};

    __global__
void filter(unsigned char *filtered, int width, int height)
{
    __shared__ int cache[BLOCK_DIM * BLOCK_DIM];

    int stride = 0;

    int tid = (blockIdx.x * gridDim.y * blockDim.x * blockDim.y) + (blockIdx.y * blockDim.x * blockDim.y) + (threadIdx.x * blockDim.y) + threadIdx.y;
    int localId = threadIdx.x * blockDim.x + threadIdx.y;

    int i = (tid + stride) % width;
    int j = (tid + stride) / width;

    while (i < width - 1 && j < height - 1)
    {
        int gradX = tex2D(imageTex, i-1, j+1) - tex2D(imageTex, i-1, j-1) + 2*tex2D(imageTex, i, j+1) - 2*tex2D(imageTex, i, j-1) + tex2D(imageTex, i+1, j+1) - tex2D(imageTex, i+1, j-1);
        int gradY = tex2D(imageTex, i-1, j-1) + 2*tex2D(imageTex, i-1, j) + tex2D(imageTex, i-1, j+1) - tex2D(imageTex, i+1, j-1) - 2*tex2D(imageTex, i+1, j) - tex2D(imageTex, i+1, j+1);

        int magnitude = (gradX * gradX) + (gradY * gradY);

        // The check for the edge pixels on the top and left boundary is made here
        // and not in the loop condition because otherwise all threads on either edges will not stride
        if (magnitude  > THRESH && i > 0 && j > 0)
        {
            cache[localId] = 255;
        }
        else
        {
            cache[localId] = 0;
        }

        __syncthreads();

        filtered[j * width + i] = cache[localId];

        stride += gridDim.x * gridDim.y * blockDim.x * blockDim.y;

        i = (tid + stride) % width;
        j = (tid + stride) / width;
    }
}

// Save an image to file
void saveImage(char*, Image*);

// Read PBM image from file
Image readImage(char*);

// Convert an image to Gray Scale
Image convertGrayScale(Image*);

// Run the sobel image filter
Image runFilter(Image*);

int main(int argc, char **argv)
{
    if (argc != 3)
    {
        printf("Usage: exec filename filename\n");
        exit(1);
    }

    char *fname = argv[1];
    char *fname2 = argv[2];

    // Read Original Image
    Image source = readImage(fname);

    // Convert to Gray Scale
    Image grayScale = convertGrayScale(&source);

    // Filter the image
    Image filtered = runFilter(&grayScale);

    // Save back to a file
    saveImage(fname2, &filtered);

    // Do civil duty and free memory
    free(source.img);
    free(grayScale.img);
    free(filtered.img);

    exit(0);
}

Image runFilter(Image *grayScale)
{
    // Creating a new black Image
    int pixels = grayScale->width * grayScale->height;
    int imageSize = grayScale->width * grayScale->height * sizeof(unsigned char);

    Image filtered;
    filtered.width = grayScale->width;
    filtered.height = grayScale->height;
    filtered.img = (unsigned char *)malloc(pixels);

    unsigned char *devGrayScale;
    unsigned char *devFiltered;

    // Initialize Cuda Memory
    CHECK(cudaMalloc(&devGrayScale, imageSize));
    CHECK(cudaMalloc(&devFiltered, imageSize));

    // Copy and Initialize Cuda Memory
    CHECK(cudaMemcpy(devGrayScale, grayScale->img, imageSize, cudaMemcpyHostToDevice));
    CHECK(cudaMemset(devFiltered, 0, imageSize));

    // Initalize texture
    cudaChannelFormatDesc desc = cudaCreateChannelDesc<unsigned char>();
    CHECK(cudaBindTexture2D(NULL, imageTex, devGrayScale, desc, grayScale->width, grayScale->height, sizeof(unsigned char) * grayScale->width));

    // Initialize Stopwatch
    cudaEvent_t event1, event2;
    cudaEventCreate(&event1);
    cudaEventCreate(&event2);
    cudaEventRecord(event1, 0);

    // Run the kernel
    // The y dimention is set 1 only to demonstrate the stride!
    dim3 dimBlock(grayScale->width/BLOCK_DIM, 1);
    dim3 dimGrid(BLOCK_DIM, BLOCK_DIM);
    filter<<<dimBlock, dimGrid>>>(devFiltered, filtered.width, filtered.height);

    // Stop Stopwatch
    cudaEventRecord(event2, 0);
    cudaEventSynchronize(event1);
    cudaEventSynchronize(event2);
    float dt_ms = 0;
    cudaEventElapsedTime(&dt_ms, event1, event2);
    printf("The filter ran in : %f seconds.\n", dt_ms);

    // Return the Cuda Memory
    CHECK(cudaMemcpy(filtered.img, devFiltered, imageSize, cudaMemcpyDeviceToHost));

    // Free Cuda Texture and Memory
    CHECK(cudaUnbindTexture(imageTex));
    CHECK(cudaFree(devGrayScale));
    CHECK(cudaFree(devFiltered));

    return filtered;
}

Image readImage(char *fname)
{
    Image source;

    FILE *src;

    if (!(src = fopen(fname, "rb")))
    {
        printf("Couldn't open file %s for reading.\n", fname);
        exit(1);
    }

    char p,s;
    fscanf(src, "%c%c\n", &p, &s);
    if (p != 'P' || s != '6')
    {
        printf("Not a valid PPM file (%c %c)\n", p, s);
        exit(1);
    }

    fscanf(src, "%d %d\n", &source.width, &source.height);
    int ignored;
    fscanf(src, "%d\n", &ignored);

    int pixels = source.width * source.height;
    source.img = (unsigned char *)malloc(pixels*3);
    if (fread(source.img, sizeof(unsigned char), pixels*3, src) != pixels*3)
    {
        printf("Error reading file.\n");
        exit(1);
    }
    fclose(src);

    return source;
}

void saveImage(char *fname, Image *source)
{
    int pixels = source->width * source->height;

    FILE *out;

    if (!(out = fopen(fname, "wb")))
    {
        printf("Couldn't open file for output.\n");
        exit(1);
    }

    fprintf(out, "P5\n%d %d\n255\n", source->width, source->height);

    if (fwrite(source->img, sizeof(unsigned char), pixels, out) != pixels)
    {
        printf("Error writing file.\n");
        exit(1);
    }

    fclose(out);
}

Image convertGrayScale(Image *source)
{
    int pixels = source->width * source->height;

    Image grayScale;
    grayScale.width = source->width;
    grayScale.height = source->height;
    grayScale.img = (unsigned char *)malloc(pixels);
    for (int i = 0; i < pixels; i++)
    {
        unsigned int r = source->img[i*3];
        unsigned int g = source->img[i*3 + 1];
        unsigned int b = source->img[i*3 + 2];
        grayScale.img[i] = 0.2989*r + 0.5870*g + 0.1140*b;
    }

    return grayScale;
}
