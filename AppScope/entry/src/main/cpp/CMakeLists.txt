cmake_minimum_required(VERSION 3.5.0)
project(native_player_bridge)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

add_library(native_player_bridge SHARED native_player_bridge.cpp)

target_include_directories(native_player_bridge PUBLIC
  ${NATIVERENDER_ROOT_PATH}
)

