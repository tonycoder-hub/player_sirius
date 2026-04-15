#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace player_sirius {

enum class PlaybackState {
    kIdle,
    kPrepared,
    kPlaying,
    kPaused,
    kStopped,
    kError,
};

inline const char* ToString(PlaybackState state)
{
    switch (state) {
        case PlaybackState::kIdle:
            return "idle";
        case PlaybackState::kPrepared:
            return "prepared";
        case PlaybackState::kPlaying:
            return "playing";
        case PlaybackState::kPaused:
            return "paused";
        case PlaybackState::kStopped:
            return "stopped";
        case PlaybackState::kError:
            return "error";
        default:
            return "unknown";
    }
}

struct SourceSpec {
    std::string source;
    std::string surface_id;
};

struct PlaybackMetrics {
    int64_t buffered_duration_ms = 0;
    int64_t decoded_audio_frames = 0;
    int64_t decoded_video_frames = 0;
    int64_t rendered_audio_frames = 0;
    int64_t rendered_video_frames = 0;
    int64_t dropped_video_frames = 0;
    int64_t emitted_events = 0;
};

struct Capability {
    bool available = false;
    std::string version = "0.3.0-p0";
    std::vector<std::string> features;
    std::string backend_name;
    std::string blocker;
    std::string stage;
};

struct StateSnapshot {
    PlaybackState state = PlaybackState::kIdle;
    std::string source;
    std::string surface_id;
    int64_t position_ms = 0;
    std::string last_error;
    std::string backend_name;
    std::string stage;
    std::string error_stage;
    PlaybackMetrics metrics;
};

struct Event {
    std::string type;
    std::string message;
    StateSnapshot snapshot;
};

} // namespace player_sirius
