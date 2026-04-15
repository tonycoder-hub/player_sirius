#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "pipeline_components.h"

namespace player_sirius {

struct AudioPcmBuffer {
    int sample_rate = 0;
    int channels = 0;
    int bytes_per_sample = 0;
    int samples_per_channel = 0;
    std::vector<uint8_t> data;
};

class AudioResampler {
public:
    AudioResampler();
    ~AudioResampler();

    bool Configure(const MediaFrame& frame, std::string* error);
    bool Convert(const MediaFrame& frame, AudioPcmBuffer* pcm, std::string* error);
    void Reset();

private:
    struct Impl;
    Impl* impl_ = nullptr;
};

} // namespace player_sirius
