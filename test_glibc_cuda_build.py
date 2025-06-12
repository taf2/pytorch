#!/usr/bin/env python
"""Test PyTorch build with glibc 2.41+ and CUDA compatibility fixes"""

import subprocess
import os
import sys
import tempfile
import shutil

def test_cuda_compilation():
    """Test if we can compile a simple CUDA program with the fixes"""
    
    test_code = '''
#include <cuda_runtime.h>
#include <cmath>
#include <cstdio>

// Test that we can use math functions
__global__ void test_kernel(float* data) {
    int idx = threadIdx.x + blockIdx.x * blockDim.x;
    // These functions should not conflict
    data[idx] = sinf(M_PI * 0.5f) + cosf(M_PI);
}

int main() {
    float* d_data;
    cudaMalloc(&d_data, sizeof(float) * 256);
    test_kernel<<<1, 256>>>(d_data);
    cudaDeviceSynchronize();
    cudaFree(d_data);
    
    printf("CUDA test successful!\\n");
    return 0;
}
'''
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.cu', delete=False) as f:
        f.write(test_code)
        test_file = f.name
    
    try:
        # Try to compile with nvcc
        cmd = [
            'nvcc',
            '-std=c++17',
            '-allow-unsupported-compiler',
            test_file,
            '-o', 'test_cuda'
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            print("✓ CUDA compilation test passed!")
            # Clean up
            if os.path.exists('test_cuda'):
                os.remove('test_cuda')
            return True
        else:
            print("✗ CUDA compilation test failed!")
            print("STDOUT:", result.stdout)
            print("STDERR:", result.stderr)
            return False
            
    finally:
        os.unlink(test_file)

def build_pytorch():
    """Build PyTorch with our fixes"""
    
    build_dir = 'build'
    
    # Clean build directory
    if os.path.exists(build_dir):
        shutil.rmtree(build_dir)
    os.makedirs(build_dir)
    
    # Run cmake
    cmake_cmd = [
        'cmake',
        '..',
        '-DUSE_CUDA=ON',
        '-DUSE_CUDNN=ON', 
        '-DCMAKE_BUILD_TYPE=Release',
        '-DTORCH_CUDA_ARCH_LIST=9.0',
        '-DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc',
        '-DCMAKE_CUDA_FLAGS=-allow-unsupported-compiler'
    ]
    
    print("Running CMake configuration...")
    os.chdir(build_dir)
    
    result = subprocess.run(cmake_cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        print("CMake configuration failed!")
        print("STDOUT:", result.stdout)
        print("STDERR:", result.stderr)
        return False
        
    print("✓ CMake configuration successful!")
    
    # Try to build a minimal target
    print("Building PyTorch...")
    make_cmd = ['make', '-j4', 'c10']
    
    result = subprocess.run(make_cmd, capture_output=True, text=True)
    
    if result.returncode == 0:
        print("✓ Build test successful!")
        return True
    else:
        print("✗ Build failed!")
        print("Last 50 lines of output:")
        lines = result.stdout.split('\n')
        for line in lines[-50:]:
            print(line)
        return False

def main():
    print("Testing PyTorch build with glibc 2.41+ CUDA compatibility fixes")
    print("=" * 60)
    
    # First test basic CUDA compilation
    if not test_cuda_compilation():
        print("\nBasic CUDA compilation failed. The glibc compatibility issue persists.")
        return 1
    
    # Then try building PyTorch
    original_dir = os.getcwd()
    try:
        if build_pytorch():
            print("\n✓ PyTorch build test completed successfully!")
            print("\nThe patch appears to be working. You can now:")
            print("1. Run the full build: python setup.py develop")
            print("2. Submit the patch as a PR to PyTorch")
            return 0
        else:
            print("\n✗ PyTorch build test failed.")
            return 1
    finally:
        os.chdir(original_dir)

if __name__ == "__main__":
    sys.exit(main())