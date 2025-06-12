# CUDAGlibcCompat.cmake
# Handles compatibility between CUDA and glibc 2.41+
# 
# glibc 2.41 added sinpi, cospi, sinpif, and cospif functions that conflict
# with CUDA's math_functions.h definitions, causing compilation failures.

function(cuda_glibc_compat_check)
  if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
    return()
  endif()

  # Check glibc version
  execute_process(
    COMMAND ldd --version
    OUTPUT_VARIABLE LDD_VERSION_OUTPUT
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
  )
  
  if(LDD_VERSION_OUTPUT MATCHES "ldd \\(.*\\) ([0-9]+)\\.([0-9]+)")
    set(GLIBC_MAJOR "${CMAKE_MATCH_1}" PARENT_SCOPE)
    set(GLIBC_MINOR "${CMAKE_MATCH_2}" PARENT_SCOPE)
    
    # Check if we have glibc 2.41 or newer
    if(CMAKE_MATCH_1 EQUAL 2 AND CMAKE_MATCH_2 GREATER_EQUAL 41)
      set(CUDA_GLIBC_COMPAT_REQUIRED TRUE PARENT_SCOPE)
      message(STATUS "Detected glibc ${CMAKE_MATCH_1}.${CMAKE_MATCH_2} - CUDA compatibility fixes will be applied")
      
      # Create an nvcc wrapper script to handle the compatibility issue
      set(NVCC_WRAPPER "${CMAKE_BINARY_DIR}/nvcc_glibc_wrapper.sh")
      file(WRITE "${NVCC_WRAPPER}" "#!/bin/bash
# NVCC wrapper for glibc 2.41+ compatibility
# This wrapper adds compatibility headers to prevent math function conflicts

# Create temporary directory for compatibility headers
COMPAT_DIR=\"\${TMPDIR:-/tmp}/cuda_glibc_compat_\$\$\"
mkdir -p \"\$COMPAT_DIR/bits\"
trap \"rm -rf \$COMPAT_DIR\" EXIT

# Create bits/mathcalls.h wrapper that prevents conflicts
cat > \"\$COMPAT_DIR/bits/mathcalls.h\" << 'EOF'
/* Wrapper to prevent glibc 2.41+ math function conflicts with CUDA */
#ifndef CUDA_GLIBC_COMPAT_MATHCALLS_H
#define CUDA_GLIBC_COMPAT_MATHCALLS_H

#ifdef __CUDACC__
  /* When CUDA is compiling, rename the conflicting functions */
  #define sinpi __glibc_sinpi_renamed
  #define cospi __glibc_cospi_renamed
  #define sinpif __glibc_sinpif_renamed
  #define cospif __glibc_cospif_renamed
#endif

#include_next <bits/mathcalls.h>

#ifdef __CUDACC__
  /* Restore the names */
  #undef sinpi
  #undef cospi
  #undef sinpif
  #undef cospif
#endif

#endif /* CUDA_GLIBC_COMPAT_MATHCALLS_H */
EOF

# Run the real nvcc with our compatibility header directory prepended
exec /usr/local/cuda/bin/nvcc -I\"\$COMPAT_DIR\" \"\$@\"
")
      
      # Make the wrapper executable
      execute_process(COMMAND chmod +x "${NVCC_WRAPPER}")
      
      # Set the CUDA compiler to use our wrapper
      set(CMAKE_CUDA_COMPILER "${NVCC_WRAPPER}" CACHE FILEPATH "CUDA compiler wrapper for glibc 2.41+" FORCE)
      
      # Also set the flags for additional safety
      set(CMAKE_CUDA_FLAGS "-allow-unsupported-compiler" CACHE STRING "" FORCE)
    endif()
  endif()
endfunction()

function(apply_cuda_glibc_compat)
  if(NOT CUDA_GLIBC_COMPAT_REQUIRED)
    return()
  endif()

  # Additional setup after CUDA is enabled
  message(STATUS "CUDA glibc 2.41+ compatibility wrapper is active")
  
  # Add compile definitions
  add_compile_definitions(
    CUDA_GLIBC_COMPAT=1
    _CUDA_GLIBC_VERSION_MAJOR=${GLIBC_MAJOR}
    _CUDA_GLIBC_VERSION_MINOR=${GLIBC_MINOR}
  )
endfunction()