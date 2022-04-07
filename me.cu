#include <assert.h>
#include <errno.h>
#include <getopt.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "dsp.h"
#include "me.cuh"

/* Motion estimation for 8x8 block */
__global__ static void me_block_8x8(struct c63_common *cm,uint8_t *orig, uint8_t *ref, int color_component)
{
  //struct macroblock *mb =&cm->curframe->mbs[color_component][mb_y*cm->padw[color_component]/8+mb_x];
  int range = cm->me_search_range;

    __shared__ int sIdx[8][8];
   //thread index
  int x_index = threadIdx.x;
  int y_index = threadIdx.y;
 
  //block index
  int block_y = blockIdx.x;
  int block_x = blockIdx.y;


  struct macroblock *mb  = &cm->curframe->mbs[color_component][block_y*cm->padw[color_component]/8+block_x];

  /* Quarter resolution for chroma channels. */
  if (color_component > 0) { range /= 2; }

  int left = block_x * 8 - range;
  int top = block_y * 8 - range;
  int right = block_x * 8 + range;
  int bottom = block_y * 8 + range;

  int w = cm->padw[color_component];
  int h = cm->padh[color_component];

  /* Make sure we are within bounds of reference frame. TODO: Support partial
     frame bounds. */
  if (left < 0) { left = 0; }
  if (top < 0) { top = 0; }
  if (right > (w - 8)) { right = w - 8; }
  if (bottom > (h - 8)) { bottom = h - 8; }

  int x, y;

  uint8_t *bl1, *bl2;
  int sad;
  int mx = block_x * 8;
  int my = block_y * 8;

  int best_sad = INT_MAX;

  for (y = top; y < bottom; ++y)
  {
    for (x = left; x < right; ++x)
    {
      sad=0;
      bl1 = orig + my*w+mx;
      bl2 = ref + y*w+x;
      //sad_block_8x8(orig + my*w+mx, ref + y*w+x, w, &sad);

      //here, sad_block_8x8 will be replaced, so that each thread can calculate their own sum absolute differences

      /* printf("(%4d,%4d) - %d\n", x, y, sad); */
      __syncthreads();
       sIdx[x_index][y_index] = abs(bl2[x_index * w + y_index] - bl1[x_index * w + y_index]);
      __syncthreads();


      //y axis
      if(y_index < 4){
        sIdx[x_index][y_index] += sIdx[x_index][7-y_index];
      }
      __syncthreads();
      if (y_index < 2) {
        sIdx[x_index][y_index] += sIdx[x_index][3-y_index];
      }
      __syncthreads();
      if (y_index < 1){
        sIdx[x_index][y_index] += sIdx[x_index][1];
      }
      __syncthreads();

      // reduce along x axis
      if(x_index < 4  && y_index == 0){
        sIdx[x_index][0] += sIdx[7-x_index][0];
      }
      __syncthreads();
      if (x_index < 2  && y_index== 0) {
        sIdx[x_index][0] += sIdx[3-x_index][0];
      }
      __syncthreads();
      if (x_index< 1 && y_index == 0){
        sIdx[x_index][y_index] += sIdx[1][y_index];
      }
      //sum
       if (x_index ==0 && y_index == 0) {
        
        sad = sIdx[0][0];

        if (sad < best_sad)
          {
          mb->mv_x = x - mx;
          mb->mv_y = y - my;
          best_sad = sad;
        }
       
     }
    }
  }
  /* Here, there should be a threshold on SAD that checks if the motion vector
     is cheaper than intraprediction. We always assume MV to be beneficial */

  /* printf("Using motion vector (%d, %d) with SAD %d\n", mb->mv_x, mb->mv_y,
     best_sad); */

  mb->use_mv = 1;
}

__global__ void c63_motion_estimate(struct c63_common *cm)
{
  /* Compare this frame with previous reconstructed frame */
  //int mb_x, mb_y;

  dim3 threads(8,8);

  /* Luma */
 
  if (threadIdx.x == 0){
    
    dim3 y_dim (cm->mb_rows, cm->mb_cols);
    me_block_8x8 <<<y_dim, threads>>>(cm, cm->curframe->orig->Y,cm->refframe->recons->Y, Y_COMPONENT);
    return; 
  }

    /* Chroma */

  if (threadIdx.x == 1){
    
    dim3 UV_dim(cm->mb_rows / 2, cm->mb_cols / 2);

    me_block_8x8<<<UV_dim, threads>>> (cm, cm->curframe->orig->U,cm->refframe->recons->U, U_COMPONENT);
    return; 
  }
  // V
  if (threadIdx.x == 2){
    
    dim3 UV_dim(cm->mb_rows / 2, cm->mb_cols / 2);

    me_block_8x8<<<UV_dim, threads>>> (cm, cm->curframe->orig->V,
      cm->refframe->recons->V, V_COMPONENT);


    return;  
  }


}

/* Motion compensation for 8x8 block */
__global__ static void mc_block_8x8(struct c63_common *cm, uint8_t *predicted, uint8_t *ref, int color_component)
{
    
  int mb_x = blockIdx.y;
  int mb_y = blockIdx.x;
  struct macroblock *mb =&cm->curframe->mbs[color_component][mb_y*cm->padw[color_component]/8+mb_x];

  if (!mb->use_mv) { return; }

  int left = mb_x * 8;
  int top = mb_y * 8;
  int right = left + 8;
  int bottom = top + 8;

  int w = cm->padw[color_component];

  /* Copy block from ref mandated by MV */
  int x, y;

  for (y = top; y < bottom; ++y)
  {
    for (x = left; x < right; ++x)
    {
      predicted[y*w+x] = ref[(y + mb->mv_y) * w + (x + mb->mv_x)];
    }
  }
}

__global__ void c63_motion_compensate(struct c63_common *cm)
{
 /* Compare this frame with previous reconstructed frame */
  //int mb_x, mb_y;

  dim3 threads(8,8);

  /* Luma */
 
  if (threadIdx.x == 0){
    
    dim3 y_dim (cm->mb_rows, cm->mb_cols);
    mc_block_8x8 <<<y_dim, threads>>>(cm, cm->curframe->orig->Y,cm->refframe->recons->Y, Y_COMPONENT);
    return; 
  }

    /* Chroma */

  if (threadIdx.x == 1){
    
    dim3 UV_dim(cm->mb_rows / 2, cm->mb_cols / 2);

    mc_block_8x8<<<UV_dim, threads>>> (cm, cm->curframe->orig->U,cm->refframe->recons->U, U_COMPONENT);
    return; 
  }
  // V
  if (threadIdx.x == 2){
    
    dim3 UV_dim(cm->mb_rows / 2, cm->mb_cols / 2);

    mc_block_8x8<<<UV_dim, threads>>> (cm, cm->curframe->orig->V,
      cm->refframe->recons->V, V_COMPONENT);


    return;  
  }

}
