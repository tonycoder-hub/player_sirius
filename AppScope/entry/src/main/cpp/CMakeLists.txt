cmake_minimum_required(VERSION 3.5.0)
project(native_player_bridge)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
get_filename_component(PLAYER_SIRIUS_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../" ABSOLUTE)
set(PLAYER_SIRIUS_THIRD_PARTY_ROOT "${PLAYER_SIRIUS_REPO_ROOT}/third_party")
set(PLAYER_SIRIUS_FFMPEG_ROOT "${PLAYER_SIRIUS_THIRD_PARTY_ROOT}/ffmpeg")

option(PLAYER_SIRIUS_ENABLE_FFMPEG "Enable FFmpeg backend lookup for Native media core" ON)

add_library(native_player_bridge SHARED
  native_player_bridge.cpp
  media_core/media_pipeline.cpp
  media_core/player_core.cpp
  media_core/platform_outputs.cpp
  media_core/soft_backend.cpp
)

target_include_directories(native_player_bridge PUBLIC
  ${NATIVERENDER_ROOT_PATH}
  ${NATIVERENDER_ROOT_PATH}/media_core
)

set(PLAYER_SIRIUS_HAS_FFMPEG 0)

if (PLAYER_SIRIUS_ENABLE_FFMPEG)
  find_path(PLAYER_SIRIUS_FFMPEG_INCLUDE_DIR
    NAMES libavcodec/avcodec.h
    PATHS
      "${PLAYER_SIRIUS_FFMPEG_ROOT}/include"
    NO_DEFAULT_PATH
  )

  find_library(PLAYER_SIRIUS_AVCODEC_LIB
    NAMES avcodec
    PATHS
      "${PLAYER_SIRIUS_FFMPEG_ROOT}/lib"
    NO_DEFAULT_PATH
  )
  find_library(PLAYER_SIRIUS_AVFORMAT_LIB
    NAMES avformat
    PATHS
      "${PLAYER_SIRIUS_FFMPEG_ROOT}/lib"
    NO_DEFAULT_PATH
  )
  find_library(PLAYER_SIRIUS_AVUTIL_LIB
    NAMES avutil
    PATHS
      "${PLAYER_SIRIUS_FFMPEG_ROOT}/lib"
    NO_DEFAULT_PATH
  )
  find_library(PLAYER_SIRIUS_SWRESAMPLE_LIB
    NAMES swresample
    PATHS
      "${PLAYER_SIRIUS_FFMPEG_ROOT}/lib"
    NO_DEFAULT_PATH
  )
  find_library(PLAYER_SIRIUS_SWSCALE_LIB
    NAMES swscale
    PATHS
      "${PLAYER_SIRIUS_FFMPEG_ROOT}/lib"
    NO_DEFAULT_PATH
  )

  if (PLAYER_SIRIUS_FFMPEG_INCLUDE_DIR
      AND PLAYER_SIRIUS_AVCODEC_LIB
      AND PLAYER_SIRIUS_AVFORMAT_LIB
      AND PLAYER_SIRIUS_AVUTIL_LIB
      AND PLAYER_SIRIUS_SWRESAMPLE_LIB
      AND PLAYER_SIRIUS_SWSCALE_LIB)
    set(PLAYER_SIRIUS_HAS_FFMPEG 1)
    target_include_directories(native_player_bridge PRIVATE ${PLAYER_SIRIUS_FFMPEG_INCLUDE_DIR})
    target_link_libraries(native_player_bridge
      ${PLAYER_SIRIUS_AVCODEC_LIB}
      ${PLAYER_SIRIUS_AVFORMAT_LIB}
      ${PLAYER_SIRIUS_AVUTIL_LIB}
      ${PLAYER_SIRIUS_SWRESAMPLE_LIB}
      ${PLAYER_SIRIUS_SWSCALE_LIB}
    )
    message(STATUS "Player Sirius: FFmpeg libraries detected under ${PLAYER_SIRIUS_FFMPEG_ROOT}")
  else()
    message(STATUS "Player Sirius: FFmpeg libraries not found under ${PLAYER_SIRIUS_FFMPEG_ROOT}; using placeholder backend")
  endif()
endif()

target_compile_definitions(native_player_bridge PRIVATE
  PLAYER_SIRIUS_HAS_FFMPEG=${PLAYER_SIRIUS_HAS_FFMPEG}
)
