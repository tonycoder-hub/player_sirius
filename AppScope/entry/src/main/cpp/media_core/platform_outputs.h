#pragma once

#include <cstdint>
#include <memory>
#include <string>

#include "pipeline_components.h"
#include "player_types.h"

namespace player_sirius {

class AudioOutput {
public:
    virtual ~AudioOutput() = default;

    virtual const char* Name() const = 0;
    virtual bool Configure(const SourceSpec& source, std::string* error) = 0;
    virtual bool Submit(const MediaFrame& frame, std::string* error) = 0;
    virtual void Reset() = 0;
    virtual void Close() = 0;
};

class PlaybackStatsCollector {
public:
    virtual ~PlaybackStatsCollector() = default;

    virtual const char* Name() const = 0;
    virtual void Reset() = 0;
    virtual void OnStageChanged(const std::string& stage) = 0;
    virtual void OnPrepared(const SourceSpec& source) = 0;
    virtual void OnPlay() = 0;
    virtual void OnPause() = 0;
    virtual void OnSeek(int64_t position_ms) = 0;
    virtual void OnDecodeFrame(bool audio, bool video) = 0;
    virtual void OnRenderFrame(bool audio, bool video) = 0;
    virtual void OnDropVideoFrame() = 0;
    virtual void OnBufferedDuration(int64_t buffered_duration_ms) = 0;
    virtual PlaybackMetrics Snapshot() const = 0;
};

std::unique_ptr<AudioOutput> CreateDefaultAudioOutput();
std::unique_ptr<PlaybackStatsCollector> CreateDefaultStatsCollector();

} // namespace player_sirius
