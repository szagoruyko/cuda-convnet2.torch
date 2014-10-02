#include "nvmatrix/include/nvmatrix_kernels.cuh"
#include "nvmatrix/include/nvmatrix_operators.cuh"
#include <THC.h>
#include <algorithm>
#include "helper_cuda.h"


__global__ void add(float* output, float* bias, int n)
{
  int ti = blockIdx.x*blockDim.x + threadIdx.x;

  if(ti >= n)
    return;

  output[ti] = bias[0];
}

extern "C" {

  void addLinearBias(THCudaTensor* output, THCudaTensor* bias)
  {
    int n = output->size[0];
    add<<< DIVUP(n,128), 128 >>> (THCudaTensor_data(output), THCudaTensor_data(bias), n);
  }
  
  void addBias(THCudaTensor* output, THCudaTensor* bias) {
    int width = output->size[1];
    int height = output->size[0];
    float *odata = THCudaTensor_data(output);
    float *bdata = THCudaTensor_data(bias);
    dim3 threads(ADD_VEC_THREADS_X, ADD_VEC_THREADS_Y);
    dim3 blocks(std::min(512, DIVUP(width, ADD_VEC_THREADS_X)),
                std::min(NUM_BLOCKS_MAX, DIVUP(height, ADD_VEC_THREADS_Y)));
    kColVectorOp<NVMatrixBinaryOps::Add>
      <<<blocks, threads>>>(odata, bdata, odata, width, height, 
                            output->stride[0], output->stride[0], 
                            NVMatrixBinaryOps::Add());
    getLastCudaError("Kernel execution failed");
  }
  
  void gradBias(THCudaTensor* gradOutput, THCudaTensor* gradBias, float scale) {
    dim3 threads(AWR_NUM_THREADS);
    dim3 blocks(1, gradOutput->size[0]);
    kAggRows_wholerow_nosync<<<blocks, threads>>>(THCudaTensor_data(gradOutput), THCudaTensor_data(gradBias), gradOutput->size[1], gradOutput->size[0], NVMatrixAggs::Sum(), NVMatrixOps::Identity(), NVMatrixBinaryOps::SecondScaled(scale));
  }
}
