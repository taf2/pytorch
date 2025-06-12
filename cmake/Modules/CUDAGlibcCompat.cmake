# CUDAGlibcCompatFixed.cmake
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
      
      # Set compiler for CUDA if not already set
      if(NOT CMAKE_CUDA_COMPILER)
        find_program(CMAKE_CUDA_COMPILER nvcc PATHS /usr/local/cuda/bin)
      endif()
      
      # Force some CUDA variables to help CMake
      set(CMAKE_CUDA_COMPILER_ID "NVIDIA" CACHE STRING "" FORCE)
      set(CMAKE_CUDA_COMPILER_FORCED TRUE CACHE BOOL "" FORCE)
      
      # Set the CUDA environment variable for CMake
      set(CMAKE_CUDA_COMPILER_ENV_VAR "CUDACXX" CACHE STRING "" FORCE)
      
      # Mark CUDA as available
      set(CMAKE_CUDA_COMPILER_LOADED 1 CACHE INTERNAL "" FORCE)
      
      # Skip compiler test when we know we have compatibility issues
      set(CMAKE_CUDA_COMPILER_WORKS TRUE CACHE INTERNAL "" FORCE)
      set(CMAKE_CUDA_ABI_COMPILED TRUE CACHE INTERNAL "" FORCE)
      
      # Create a fake CMakeCUDACompiler.cmake to bypass the check
      if(CMAKE_CUDA_COMPILER)
        execute_process(
          COMMAND ${CMAKE_CUDA_COMPILER} --version
          OUTPUT_VARIABLE NVCC_VERSION_OUTPUT
          OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if(NVCC_VERSION_OUTPUT MATCHES "release ([0-9]+)\\.([0-9]+)")
          set(CMAKE_CUDA_COMPILER_VERSION "${CMAKE_MATCH_1}.${CMAKE_MATCH_2}" CACHE STRING "" FORCE)
        endif()
      endif()
      
      # Generate the compiler info file
      set(CMAKE_PLATFORM_INFO_DIR "${CMAKE_BINARY_DIR}/CMakeFiles/${CMAKE_VERSION}")
      file(MAKE_DIRECTORY "${CMAKE_PLATFORM_INFO_DIR}")
      configure_file(
        "${CMAKE_SOURCE_DIR}/cmake/Modules/CMakeCUDACompiler.cmake.in"
        "${CMAKE_PLATFORM_INFO_DIR}/CMakeCUDACompiler.cmake"
        @ONLY
      )
    endif()
  endif()
endfunction()

function(apply_cuda_glibc_compat)
  if(NOT CUDA_GLIBC_COMPAT_REQUIRED)
    return()
  endif()

  # Create a wrapper header that prevents the conflicts
  set(CUDA_COMPAT_DIR "${CMAKE_BINARY_DIR}/cuda_compat")
  file(MAKE_DIRECTORY "${CUDA_COMPAT_DIR}")
  
  # Create bits/mathcalls.h wrapper that prevents glibc from declaring conflicting functions
  file(WRITE "${CUDA_COMPAT_DIR}/bits/mathcalls.h" "
/* Wrapper to prevent glibc 2.41+ math function conflicts with CUDA */
#ifndef CUDA_GLIBC_COMPAT_MATHCALLS_H
#define CUDA_GLIBC_COMPAT_MATHCALLS_H

/* When compiling CUDA code, prevent sinpi/cospi declarations */
#ifdef __CUDACC__
  /* Undefine the macros that would declare sinpi/cospi/etc */
  #undef __MATHCALL
  #define __MATHCALL(function, suffix, args) 
  #undef __MATHDECL
  #define __MATHDECL(type, function, suffix, args)
  #undef __MATHDECL_1
  #define __MATHDECL_1(type, function, suffix, args)
  
  /* Include the real mathcalls.h with our safety defines */
  #include_next <bits/mathcalls.h>
  
  /* Restore the macros */
  #undef __MATHCALL
  #undef __MATHDECL
  #undef __MATHDECL_1
#else
  /* For non-CUDA code, just include normally */
  #include_next <bits/mathcalls.h>
#endif

#endif /* CUDA_GLIBC_COMPAT_MATHCALLS_H */
")

  # Create crt/math_functions.h wrapper
  set(CUDA_COMPAT_CRT_DIR "${CUDA_COMPAT_DIR}/crt")
  file(MAKE_DIRECTORY "${CUDA_COMPAT_CRT_DIR}")
  
  file(WRITE "${CUDA_COMPAT_CRT_DIR}/math_functions.h" "
/* Wrapper for CUDA math_functions.h to handle glibc 2.41+ conflicts */
#ifndef CUDA_GLIBC_COMPAT_MATH_FUNCTIONS_H
#define CUDA_GLIBC_COMPAT_MATH_FUNCTIONS_H

/* Prevent glibc from declaring conflicting functions */
#define _GNU_SOURCE 1

/* Save any existing definitions */
#pragma push_macro(\"sinpi\")
#pragma push_macro(\"cospi\")
#pragma push_macro(\"sinpif\")
#pragma push_macro(\"cospif\")

/* Undefine to prevent conflicts */
#undef sinpi
#undef cospi  
#undef sinpif
#undef cospif

/* Include the actual CUDA math_functions.h */
#include_next <crt/math_functions.h>

/* Restore the macros */
#pragma pop_macro(\"sinpi\")
#pragma pop_macro(\"cospi\")
#pragma pop_macro(\"sinpif\")
#pragma pop_macro(\"cospif\")

#endif /* CUDA_GLIBC_COMPAT_MATH_FUNCTIONS_H */
")

  # Add our wrapper directory to the include path BEFORE system includes
  # This ensures our wrappers are found first
  include_directories(BEFORE SYSTEM "${CUDA_COMPAT_DIR}")
  
  # Add necessary CUDA flags
  list(APPEND CMAKE_CUDA_FLAGS 
    "-I${CUDA_COMPAT_DIR}"
    "-allow-unsupported-compiler"
  )
  
  # Also set for regular C/C++ compilation that might include CUDA headers
  add_compile_options(
    "-I${CUDA_COMPAT_DIR}"
  )
  
  # Export the flags
  set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS}" PARENT_SCOPE)
  
  # Add compile definitions
  add_compile_definitions(
    CUDA_GLIBC_COMPAT=1
    _CUDA_GLIBC_VERSION_MAJOR=${GLIBC_MAJOR}
    _CUDA_GLIBC_VERSION_MINOR=${GLIBC_MINOR}
  )
endfunction()