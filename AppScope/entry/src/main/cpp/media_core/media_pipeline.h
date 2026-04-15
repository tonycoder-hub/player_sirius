#pragma once

#include <cstdint>
#include <memory>
#include <string>

#include "platform_outputs.h"
#include "pipeline_components.h"

namespace player_sirius {

class MediaPipeline {
public:
    MediaPipeline(
        std::unique_ptr<Demuxer> demuxer,
        std::unique_ptr<Decoder> decoder,
        std::unique_ptr<Renderer> renderer,
        std::unique_ptr<AudioOutput> audio_output,
        std::unique_ptr<Clock> clock,
        std::unique_ptr<PlaybackStatsCollector> stats_collector);
    ~MediaPipeline();

    bool Prepare(const SourceSpec& source, std::string* error);
    bool Play(std::string* error);
    bool Pause(std::string* error);
    bool Stop(std::string* error);
    bool Seek(int64_t position_ms, std::string* error);
    void Release();

    std::string Stage() const;
    PlaybackMetrics Metrics() const;

private:
    void SetStage(const std::string& stage);

    std::unique_ptr<Demuxer> demuxer_;
    std::unique_ptr<Decoder> decoder_;
    std::unique_ptr<Renderer> renderer_;
    std::unique_ptr<AudioOutput> audio_output_;
    std::unique_ptr<Clock> clock_;
    std::unique_ptr<PlaybackStatsCollector> stats_collector_;
    SourceSpec source_;
    std::string stage_ = "idle";
    bool prepared_ = false;
    bool playing_ = false;
};

std::unique_ptr<MediaPipeline> CreateDefaultMediaPipeline();

} // namespace player_sirius
