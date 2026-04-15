#pragma once

#include <cstdint>
#include <memory>
#include <string>

#include "media_pipeline.h"
#include "player_types.h"

namespace player_sirius {

class SoftDecodeBackend {
public:
    virtual ~SoftDecodeBackend() = default;

    virtual Capability GetCapability() const = 0;
    virtual std::string GetStage() const = 0;
    virtual PlaybackMetrics GetMetrics() const = 0;
    virtual bool Prepare(const SourceSpec& source, std::string* error) = 0;
    virtual bool Play(std::string* error) = 0;
    virtual bool Pause(std::string* error) = 0;
    virtual bool Stop(std::string* error) = 0;
    virtual bool Seek(int64_t position_ms, std::string* error) = 0;
    virtual void Release() = 0;
};

std::unique_ptr<SoftDecodeBackend> CreateSoftDecodeBackend();

} // namespace player_sirius
