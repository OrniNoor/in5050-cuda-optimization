#ifndef C63_ME_CUH_
#define C63_ME_CUH_

#include "c63.cuh"

// Declaration
__global__ void c63_motion_estimate(struct c63_common *cm);
__global__ void c63_motion_compensate(struct c63_common *cm);
__global__ static void me_block_8x8(struct c63_common *cm,uint8_t *orig, uint8_t *ref, int color_component);
__global__ static void mc_block_8x8(struct c63_common *cm, uint8_t *predicted, uint8_t *ref, int color_component);

#endif  /* C63_ME_H_ */
