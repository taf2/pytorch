#pragma once
/*
 * CUDAMathCompat.h
 * 
 * Compatibility layer for CUDA math functions with glibc 2.41+
 * 
 * glibc 2.41 added sinpi, cospi, sinpif, and cospif functions that conflict
 * with CUDA's math_functions.h. This header provides a compatibility layer.
 */

#ifdef __CUDACC__

// Check if we're dealing with glibc 2.41+ conflict
#if defined(__GLIBC__) && defined(__GLIBC_MINOR__) && (__GLIBC__ == 2 && __GLIBC_MINOR__ >= 41)
  #define CUDA_GLIBC_MATH_CONFLICT 1
#endif

#ifdef CUDA_GLIBC_MATH_CONFLICT
  // Save the original functions if they exist
  #ifdef sinpi
    #define _GLIBC_sinpi sinpi
    #undef sinpi
  #endif
  #ifdef cospi
    #define _GLIBC_cospi cospi
    #undef cospi
  #endif
  #ifdef sinpif
    #define _GLIBC_sinpif sinpif
    #undef sinpif
  #endif
  #ifdef cospif
    #define _GLIBC_cospif cospif
    #undef cospif
  #endif
#endif

// Include CUDA's math functions
#include <cuda_runtime.h>
#include <math_functions.h>

#ifdef CUDA_GLIBC_MATH_CONFLICT
namespace at { namespace cuda { namespace compat {

// Provide inline wrappers that resolve to the correct function
// based on whether we're in device or host code
__device__ __host__ inline double sinpi(double x) {
  #ifdef __CUDA_ARCH__
    // Device code: use CUDA's sinpi
    return ::sinpi(x);
  #else
    // Host code: compute sin(pi * x)
    return sin(M_PI * x);
  #endif
}

__device__ __host__ inline double cospi(double x) {
  #ifdef __CUDA_ARCH__
    // Device code: use CUDA's cospi
    return ::cospi(x);
  #else
    // Host code: compute cos(pi * x)
    return cos(M_PI * x);
  #endif
}

__device__ __host__ inline float sinpif(float x) {
  #ifdef __CUDA_ARCH__
    // Device code: use CUDA's sinpif
    return ::sinpif(x);
  #else
    // Host code: compute sinf(pi * x)
    return sinf(static_cast<float>(M_PI) * x);
  #endif
}

__device__ __host__ inline float cospif(float x) {
  #ifdef __CUDA_ARCH__
    // Device code: use CUDA's cospif
    return ::cospif(x);
  #else
    // Host code: compute cosf(pi * x)
    return cosf(static_cast<float>(M_PI) * x);
  #endif
}

}}} // namespace at::cuda::compat

// For backward compatibility, make these available in global namespace
// when compiling device code
#ifdef __CUDA_ARCH__
using at::cuda::compat::sinpi;
using at::cuda::compat::cospi;
using at::cuda::compat::sinpif;
using at::cuda::compat::cospif;
#endif

#endif // CUDA_GLIBC_MATH_CONFLICT

#endif // __CUDACC__