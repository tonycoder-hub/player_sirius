#pragma once

#include <cstdint>

namespace player_sirius {

enum class VideoSyncAction {
    kRenderNow,
    kWait,
    kDrop,
};

struct VideoSyncDecision {
    VideoSyncAction action = VideoSyncAction::kRenderNow;
    int64_t delay_ms = 0;
    int64_t delta_ms = 0;
};

class SyncController {
public:
    void Reset();
    void OnSeek(int64_t position_ms);
    void OnAudioRendered(int64_t pts_ms);
    void OnVideoRendered(int64_t pts_ms);

    int64_t MasterClockMs() const;
    VideoSyncDecision DecideVideoFrame(int64_t video_pts_ms, int64_t fallback_clock_ms) const;

private:
    int64_t audio_clock_ms_ = 0;
    int64_t video_clock_ms_ = 0;
    bool has_audio_clock_ = false;
    bool has_video_clock_ = false;
};

} // namespace player_sirius
