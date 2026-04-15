#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "pipeline_components.h"

namespace player_sirius {

struct VideoPixelBuffer {
    int width = 0;
    int height = 0;
    int stride = 0;
    std::vector<uint8_t> rgba;
};

class VideoConverter {
public:
    VideoConverter();
    ~VideoConverter();

    bool Configure(const MediaFrame& frame, std::string* error);
    bool Convert(const MediaFrame& frame, VideoPixelBuffer* buffer, std::string* error);
    void Reset();

private:
    struct Impl;
    Impl* impl_ = nullptr;
};

} // namespace player_sirius
