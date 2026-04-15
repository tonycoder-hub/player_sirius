cmake_minimum_required(VERSION 3.5.0)
project(native_player_bridge)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
get_filename_component(PLAYER_SIRIUS_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../" ABSOLUTE)
set(PLAYER_SIRIUS_THIRD_PARTY_ROOT "${PLAYER_SIRIUS_REPO_ROOT}/third_party")
set(PLAYER_SIRIUS_FFMPEG_ROOT "${PLAYER_SIRIUS_THIRD_PARTY_ROOT}/ffmpeg")
set(PLAYER_SIRIUS_LIBSMB2_ROOT "${PLAYER_SIRIUS_THIRD_PARTY_ROOT}/libsmb2")
set(PLAYER_SIRIUS_LIBSMB2_SOURCE_DIR "${PLAYER_SIRIUS_LIBSMB2_ROOT}/upstream")

option(PLAYER_SIRIUS_ENABLE_FFMPEG "Enable FFmpeg backend lookup for Native media core" ON)
option(PLAYER_SIRIUS_ENABLE_LIBSMB2 "Enable libsmb2 backend lookup for SMB bridge" ON)

find_path(PLAYER_SIRIUS_NODE_API_INCLUDE_DIR
  NAMES node_api.h
  PATHS
    /usr/include/node
    /usr/local/include/node
    /opt/homebrew/include/node
    /home/linuxbrew/.linuxbrew/include/node
)

add_library(native_player_bridge SHARED
  native_player_bridge.cpp
  media_core/audio_resampler.cpp
  media_core/ffmpeg_decoder.cpp
  media_core/ffmpeg_demuxer.cpp
  media_core/media_pipeline.cpp
  media_core/player_core.cpp
  media_core/platform_outputs.cpp
  media_core/soft_backend.cpp
  media_core/sync_controller.cpp
  media_core/video_converter.cpp
)

add_library(smb_client_bridge SHARED
  smb_client_bridge.cpp
)

target_include_directories(native_player_bridge PUBLIC
  ${NATIVERENDER_ROOT_PATH}
  ${NATIVERENDER_ROOT_PATH}/media_core
)

target_include_directories(smb_client_bridge PUBLIC
  ${NATIVERENDER_ROOT_PATH}
)

if (PLAYER_SIRIUS_NODE_API_INCLUDE_DIR)
  target_include_directories(native_player_bridge PRIVATE ${PLAYER_SIRIUS_NODE_API_INCLUDE_DIR})
  target_include_directories(smb_client_bridge PRIVATE ${PLAYER_SIRIUS_NODE_API_INCLUDE_DIR})
  message(STATUS "Player Sirius: node_api.h detected under ${PLAYER_SIRIUS_NODE_API_INCLUDE_DIR}")
else()
  message(WARNING "Player Sirius: node_api.h not found; NAPI bridge targets may fail to compile")
endif()

set(PLAYER_SIRIUS_HAS_FFMPEG 0)
set(PLAYER_SIRIUS_HAS_LIBSMB2 0)

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

if (PLAYER_SIRIUS_ENABLE_LIBSMB2)
  if (EXISTS "${PLAYER_SIRIUS_LIBSMB2_SOURCE_DIR}/CMakeLists.txt")
    set(PLAYER_SIRIUS_HAS_LIBSMB2 1)
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    set(CMAKE_POSITION_INDEPENDENT_CODE ON CACHE BOOL "" FORCE)
    set(ENABLE_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(ENABLE_LIBKRB5 OFF CACHE BOOL "" FORCE)
    set(ENABLE_GSSAPI OFF CACHE BOOL "" FORCE)
    add_subdirectory("${PLAYER_SIRIUS_LIBSMB2_SOURCE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/libsmb2_build" EXCLUDE_FROM_ALL)
    target_link_libraries(smb_client_bridge smb2)
    message(STATUS "Player Sirius: using vendored libsmb2 source under ${PLAYER_SIRIUS_LIBSMB2_SOURCE_DIR}")
  else()
    find_path(PLAYER_SIRIUS_LIBSMB2_INCLUDE_DIR
      NAMES smb2/smb2.h
      PATHS
        "${PLAYER_SIRIUS_LIBSMB2_ROOT}/include"
      NO_DEFAULT_PATH
    )

    find_library(PLAYER_SIRIUS_LIBSMB2_LIB
      NAMES smb2 libsmb2
      PATHS
        "${PLAYER_SIRIUS_LIBSMB2_ROOT}/lib"
      NO_DEFAULT_PATH
    )

    if (PLAYER_SIRIUS_LIBSMB2_INCLUDE_DIR AND PLAYER_SIRIUS_LIBSMB2_LIB)
      set(PLAYER_SIRIUS_HAS_LIBSMB2 1)
      target_include_directories(smb_client_bridge PRIVATE ${PLAYER_SIRIUS_LIBSMB2_INCLUDE_DIR})
      target_link_libraries(smb_client_bridge ${PLAYER_SIRIUS_LIBSMB2_LIB})
      message(STATUS "Player Sirius: using prebuilt libsmb2 under ${PLAYER_SIRIUS_LIBSMB2_ROOT}")
    else()
      message(STATUS "Player Sirius: libsmb2 source/lib not found under ${PLAYER_SIRIUS_LIBSMB2_ROOT}; using placeholder SMB bridge")
    endif()
  endif()
endif()

target_compile_definitions(smb_client_bridge PRIVATE
  PLAYER_SIRIUS_HAS_LIBSMB2=${PLAYER_SIRIUS_HAS_LIBSMB2}
)
