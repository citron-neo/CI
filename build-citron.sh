#!/bin/sh
set -ex

# --- Architecture and Compiler Flag Setup ---
ARCH="${ARCH:-$(uname -m)}"

if [ "$1" = 'v3' ] && [ "$ARCH" = 'x86_64' ]; then
    ARCH_FLAGS="-march=x86-64-v3 -O3 -USuccess -UNone -fuse-ld=lld"
elif [ "$ARCH" = 'x86_64' ]; then
    ARCH_FLAGS="-march=x86-64 -mtune=generic -O3 -USuccess -UNone -fuse-ld=lld"
else
    ARCH_FLAGS="-march=armv8-a -mtune=generic -O3 -USuccess -UNone -fuse-ld=lld"
fi

# --- Source Code Checkout and Versioning ---
git clone --recurse-submodules --shallow-submodules --depth 1 "https://github.com/citron-neo/emulator.git" ./citron
cd ./citron

if [ "$DEVEL" = 'true' ]; then
    CITRON_TAG="$(git rev-parse --short HEAD)"
    VERSION="$CITRON_TAG"
else
    CITRON_TAG=$(git describe --tags)
    git checkout "$CITRON_TAG"
    VERSION="$(echo "$CITRON_TAG" | awk -F'-' '{print $1}')"
fi

# --- Apply Necessary Source Code Patches for Compatibility ---
find . -type f \( -name '*.cpp' -o -name '*.h' \) | xargs sed -i 's/\bboost::asio::io_service\b/boost::asio::io_context/g'
find . -type f \( -name '*.cpp' -o -name '*.h' \) | xargs sed -i 's/\bboost::asio::io_service::strand\b/boost::asio::strand<boost::asio::io_context::executor_type>/g'
find . -type f \( -name '*.cpp' -o -name '*.h' \) | xargs sed -i 's|#include *<boost/process/async_pipe.hpp>|#include <boost/process/v1/async_pipe.hpp>|g'
find . -type f \( -name '*.cpp' -o -name '*.h' \) | xargs sed -i 's/\bboost::process::async_pipe\b/boost::process::v1::async_pipe/g'
sed -i '/sse2neon/d' ./src/video_core/CMakeLists.txt
sed -i 's/cmake_minimum_required(VERSION 2.8)/cmake_minimum_required(VERSION 3.5)/' externals/xbyak/CMakeLists.txt

# --- Find Qt6 Private Headers ---
HEADER_PATH=$(pacman -Ql qt6-base | grep 'qpa/qplatformnativeinterface.h$' | awk '{print $2}')
if [ -z "$HEADER_PATH" ]; then
    echo "ERROR: Could not find qplatformnativeinterface.h path." >&2
    exit 1
fi
QT_PRIVATE_INCLUDE_DIR=$(dirname "$(dirname "$HEADER_PATH")")
CXX_FLAGS_EXTRA="-I${QT_PRIVATE_INCLUDE_DIR}"

# --- Build Process ---
JOBS=$(nproc --all)

mkdir build && cd build

# Configure the build using CMake
cmake .. -GNinja \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DCITRON_USE_BUNDLED_VCPKG=OFF \
    -DCITRON_USE_BUNDLED_QT=OFF \
    -DUSE_SYSTEM_QT=ON \
    -DENABLE_QT6=ON \
    -DCITRON_USE_BUNDLED_FFMPEG=OFF \
    -DCITRON_USE_BUNDLED_SDL2=ON \
    -DCITRON_USE_EXTERNAL_SDL2=OFF \
    -DCITRON_TESTS=OFF \
    -DCITRON_CHECK_SUBMODULES=OFF \
    -DCITRON_USE_LLVM_DEMANGLE=OFF \
    -DCITRON_ENABLE_LTO=ON \
    -DCITRON_USE_QT_MULTIMEDIA=ON \
    -DCITRON_USE_QT_WEB_ENGINE=OFF \
    -DENABLE_QT_TRANSLATION=ON \
    -DUSE_DISCORD_PRESENCE=ON \
    -DENABLE_WEB_SERVICE=ON \
    -DENABLE_OPENSSL=ON \
    -DBUNDLE_SPEEX=ON \
    -DCITRON_USE_FASTER_LD=OFF \
    -DCITRON_USE_EXTERNAL_Vulkan_HEADERS=ON \
    -DCITRON_USE_EXTERNAL_VULKAN_UTILITY_LIBRARIES=ON \
    -DCITRON_USE_AUTO_UPDATER=ON \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_CXX_FLAGS="$ARCH_FLAGS -Wno-error -w ${CXX_FLAGS_EXTRA}" \
    -DCMAKE_C_FLAGS="$ARCH_FLAGS" \
    -DCMAKE_SYSTEM_PROCESSOR="$(uname -m)" \
    -DCITRON_BUILD_TYPE=Release \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5

# Compile and install the project
ninja -j${JOBS}
sudo ninja install

# --- Output Version Info ---
echo "$VERSION" >~/version
