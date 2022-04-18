#!/bin/bash

cd `dirname $0`

set -ex

PACKAGE_NAME=archlinux_x86_64
PROJECT_DIR=`pwd`/..
SCRIPT_DIR=$PROJECT_DIR/script
SOURCE_DIR=$PROJECT_DIR/_source/$PACKAGE_NAME
BUILD_DIR=$PROJECT_DIR/_build/$PACKAGE_NAME
INSTALL_DIR=$PROJECT_DIR/_install/$PACKAGE_NAME

mkdir -p $SOURCE_DIR
mkdir -p $BUILD_DIR
mkdir -p $INSTALL_DIR

source $PROJECT_DIR/VERSION
CURRENT_VERSION="`cat $PROJECT_DIR/VERSION`"
INSTALLED_VERSION=""
if [ -e $INSTALL_DIR/VERSION ]; then
  INSTALLED_VERSION="`cat $INSTALL_DIR/VERSION`"
fi

if [ "$CURRENT_VERSION" != "$INSTALLED_VERSION" ]; then
  # WebRTC の取得
  $SCRIPT_DIR/get_webrtc.sh "$WEBRTC_BUILD_VERSION" ubuntu-20.04_x86_64 $INSTALL_DIR $SOURCE_DIR

  # コンパイラの取得
  $SCRIPT_DIR/get_llvm.sh $INSTALL_DIR/webrtc $INSTALL_DIR

  # Boost のビルド
  $SCRIPT_DIR/setup_boost.sh $BOOST_VERSION $SOURCE_DIR/boost $SOURCE_DIR
  pushd $SOURCE_DIR/boost/source
    mkdir -p $BUILD_DIR/boost
    echo "using clang : : $INSTALL_DIR/llvm/clang/bin/clang++ : ;" > project-config.jam
    ./b2 \
      cxxstd=17 \
      cxxflags=" \
        -D_LIBCPP_ABI_UNSTABLE \
        -D_LIBCPP_DISABLE_AVAILABILITY \
        -nostdinc++ \
        -isystem${INSTALL_DIR}/llvm/libcxx/include \
        -fPIC \
      " \
      linkflags=' \
      ' \
      toolset=clang \
      visibility=global \
      target-os=linux \
      address-model=64 \
      link=static \
      variant=release \
      install \
      -j`nproc` \
      --build-dir=$BUILD_DIR/boost \
      --ignore-site-config \
      --prefix=$INSTALL_DIR/boost \
      --with-filesystem \
      --with-json

  # CLI11 の取得
  rm -rf $INSTALL_DIR/CLI11
  git clone --branch v$CLI11_VERSION --depth 1 https://github.com/CLIUtils/CLI11.git $INSTALL_DIR/CLI11

  # CMake のインストール
  $SCRIPT_DIR/get_cmake.sh "$CMAKE_VERSION" linux $INSTALL_DIR
  export PATH="$INSTALL_DIR/cmake/bin:$PATH"

  # SDL2 のビルド
  $SCRIPT_DIR/setup_sdl2.sh "$SDL2_VERSION" $SOURCE_DIR/sdl2
  mkdir -p $BUILD_DIR/sdl2/
  pushd $BUILD_DIR/sdl2
    cmake $SOURCE_DIR/sdl2/source \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR/SDL2 \
      -DCMAKE_C_COMPILER=$INSTALL_DIR/llvm/clang/bin/clang \
      -DCMAKE_CXX_COMPILER=$INSTALL_DIR/llvm/clang/bin/clang++ \
      -DBUILD_SHARED_LIBS=OFF \
      -DSDL_ATOMIC=OFF \
      -DSDL_AUDIO=OFF \
      -DSDL_VIDEO=ON \
      -DSDL_RENDER=ON \
      -DSDL_EVENTS=ON \
      -DSDL_JOYSTICK=ON \
      -DSDL_HAPTIC=ON \
      -DSDL_POWER=ON \
      -DSDL_THREADS=ON \
      -DSDL_TIMERS=OFF \
      -DSDL_FILE=OFF \
      -DSDL_LOADSO=ON \
      -DSDL_CPUINFO=OFF \
      -DSDL_FILESYSTEM=OFF \
      -DSDL_DLOPEN=ON \
      -DSDL_SENSOR=ON \
      -DVIDEO_OPENGL=ON \
      -DVIDEO_OPENGLES=ON \
      -DVIDEO_RPI=OFF \
      -DVIDEO_WAYLAND=OFF \
      -DVIDEO_X11=ON \
      -DX11_SHARED=OFF \
      -DVIDEO_X11_XCURSOR=OFF \
      -DVIDEO_X11_XINERAMA=OFF \
      -DVIDEO_X11_XINPUT=OFF \
      -DVIDEO_X11_XRANDR=OFF \
      -DVIDEO_X11_XVM=OFF \
      -DVIDEO_VULKAN=OFF \
      -DVIDEO_VIVANTE=OFF \
      -DVIDEO_COCOA=OFF \
      -DVIDEO_METAL=OFF \
      -DVIDEO_KMSDRM=OFF \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON

    # Temporary hack
    sed -i 's/-DNDEBUG/-DNDEBUG -fPIC/g' $BUILD_DIR/sdl2/CMakeFiles/SDL2-static.dir/flags.make

    make -j`nproc`
    make install
  popd

  cp $PROJECT_DIR/VERSION $INSTALL_DIR/VERSION
fi

source $INSTALL_DIR/webrtc/VERSIONS

export PATH="$INSTALL_DIR/cmake/bin:$PATH"

pushd $PROJECT_DIR
  MOMO_COMMIT="`git rev-parse HEAD`"
  MOMO_COMMIT_SHORT="`cat $MOMO_COMMIT | cut -b 1-8`"
popd

mkdir -p $BUILD_DIR/momo
pushd $BUILD_DIR/momo
  cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DMOMO_VERSION=$MOMO_VERSION \
    -DMOMO_COMMIT=$MOMO_COMMIT \
    -DWEBRTC_BUILD_VERSION=$WEBRTC_BUILD_VERSION \
    -DWEBRTC_READABLE_VERSION="$WEBRTC_READABLE_VERSION" \
    -DWEBRTC_COMMIT="$WEBRTC_COMMIT" \
    -DBOOST_ROOT_DIR=$INSTALL_DIR/boost \
    -DCLI11_ROOT_DIR=$INSTALL_DIR/CLI11 \
    -DSDL2_ROOT_DIR=$INSTALL_DIR/SDL2 \
    -DWEBRTC_INCLUDE_DIR=$INSTALL_DIR/webrtc/include \
    -DWEBRTC_LIBRARY_DIR=$INSTALL_DIR/webrtc/lib \
    -DLIBCXX_INCLUDE_DIR=$INSTALL_DIR/llvm/libcxx/include \
    -DTARGET_OS="linux" \
    -DTARGET_OS_LINUX="archlinux" \
    -DTARGET_ARCH="x86_64" \
    -DUSE_H264=ON \
    -DUSE_SDL2=ON \
    -DUSE_NVCODEC_ENCODER=ON \
    -DUSE_SCREEN_CAPTURER=ON \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DUSE_LIBCXX=ON \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    $PROJECT_DIR

  # Temporary hack
  sed -i 's%-I/usr/local/cuda%-I/opt/cuda%g' $BUILD_DIR/momo/CMakeFiles/momo.dir/flags.make
  sed -i 's%/usr/local/cuda%/opt/cuda%g' $BUILD_DIR/momo/CMakeFiles/momo.dir/link.txt
  sed -i 's%--cuda-gpu-arch=sm_35%--cuda-gpu-arch=sm_61%g' $BUILD_DIR/momo/CMakeFiles/momo.dir/flags.make
  sed -i 's%--cuda-gpu-arch=sm_35%--cuda-gpu-arch=sm_61 --cuda-path=/opt/cuda%g' $BUILD_DIR/momo/CMakeFiles/momo.dir/build.make

  cmake --build . -j`nproc`
popd
