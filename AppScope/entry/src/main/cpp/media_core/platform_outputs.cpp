#include "platform_outputs.h"

#include <algorithm>

namespace player_sirius {

namespace {

#if PLAYER_SIRIUS_HAS_FFMPEG
constexpr const char* kAudioOutputBlocker = "Audio sink interface is ready, but platform audio output is not implemented yet";
#else
constexpr const char* kAudioOutputBlocker = "Audio output backend is not linked";
#endif

class PlaceholderAudioOutput final : public AudioOutput {
public:
    const char* Name() const override
    {
        return "placeholder-audio-output";
    }

    bool Configure(const SourceSpec& source, std::string* error) override
    {
        source_ = source;
        if (source.source.empty()) {
            Assign(error, "audio output source is empty");
            return false;
        }
        Assign(error, kAudioOutputBlocker);
        return false;
    }

    bool Submit(const MediaFrame& frame, std::string* error) override
    {
        last_pts_ms_ = frame.pts_ms;
        Assign(error, kAudioOutputBlocker);
        return false;
    }

    void Reset() override
    {
        last_pts_ms_ = 0;
    }

    void Close() override
    {
        source_ = SourceSpec();
        last_pts_ms_ = 0;
    }

private:
    static void Assign(std::string* error, const std::string& message)
    {
        if (error != nullptr) {
            *error = message;
        }
    }

    SourceSpec source_;
    int64_t last_pts_ms_ = 0;
};

class SimpleStatsCollector final : public PlaybackStatsCollector {
public:
    const char* Name() const override
    {
        return "simple-stats-collector";
    }

    void Reset() override
    {
        metrics_ = PlaybackMetrics();
        last_stage_.clear();
    }

    void OnStageChanged(const std::string& stage) override
    {
        last_stage_ = stage;
        metrics_.emitted_events += 1;
    }

    void OnPrepared(const SourceSpec& source) override
    {
        (void)source;
        metrics_.buffered_duration_ms = 0;
    }

    void OnPlay() override
    {
        metrics_.emitted_events += 1;
    }

    void OnPause() override
    {
        metrics_.emitted_events += 1;
    }

    void OnSeek(int64_t position_ms) override
    {
        metrics_.buffered_duration_ms = std::max<int64_t>(0, metrics_.buffered_duration_ms - position_ms);
    }

    void OnDecodeFrame(bool audio, bool video) override
    {
        if (audio) {
            metrics_.decoded_audio_frames += 1;
        }
        if (video) {
            metrics_.decoded_video_frames += 1;
        }
    }

    void OnRenderFrame(bool audio, bool video) override
    {
        if (audio) {
            metrics_.rendered_audio_frames += 1;
        }
        if (video) {
            metrics_.rendered_video_frames += 1;
        }
    }

    void OnDropVideoFrame() override
    {
        metrics_.dropped_video_frames += 1;
    }

    void OnBufferedDuration(int64_t buffered_duration_ms) override
    {
        metrics_.buffered_duration_ms = std::max<int64_t>(0, buffered_duration_ms);
    }

    PlaybackMetrics Snapshot() const override
    {
        return metrics_;
    }

private:
    PlaybackMetrics metrics_;
    std::string last_stage_;
};

} // namespace

std::unique_ptr<AudioOutput> CreateDefaultAudioOutput()
{
    return std::make_unique<PlaceholderAudioOutput>();
}

std::unique_ptr<PlaybackStatsCollector> CreateDefaultStatsCollector()
{
    return std::make_unique<SimpleStatsCollector>();
}

} // namespace player_sirius
