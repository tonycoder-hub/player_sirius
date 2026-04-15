#include "sync_controller.h"

#include <algorithm>

namespace player_sirius {

void SyncController::Reset()
{
    audio_clock_ms_ = 0;
    video_clock_ms_ = 0;
    has_audio_clock_ = false;
    has_video_clock_ = false;
}

void SyncController::OnSeek(int64_t position_ms)
{
    audio_clock_ms_ = std::max<int64_t>(0, position_ms);
    video_clock_ms_ = std::max<int64_t>(0, position_ms);
    has_audio_clock_ = true;
    has_video_clock_ = true;
}

void SyncController::OnAudioRendered(int64_t pts_ms)
{
    audio_clock_ms_ = std::max<int64_t>(0, pts_ms);
    has_audio_clock_ = true;
}

void SyncController::OnVideoRendered(int64_t pts_ms)
{
    video_clock_ms_ = std::max<int64_t>(0, pts_ms);
    has_video_clock_ = true;
}

int64_t SyncController::MasterClockMs() const
{
    if (has_audio_clock_) {
        return audio_clock_ms_;
    }
    if (has_video_clock_) {
        return video_clock_ms_;
    }
    return 0;
}

VideoSyncDecision SyncController::DecideVideoFrame(int64_t video_pts_ms, int64_t fallback_clock_ms) const
{
    const int64_t master_clock_ms = has_audio_clock_ ? audio_clock_ms_ : fallback_clock_ms;
    const int64_t delta_ms = std::max<int64_t>(-5000, std::min<int64_t>(5000, video_pts_ms - master_clock_ms));

    VideoSyncDecision decision;
    decision.delta_ms = delta_ms;
    if (delta_ms < -80) {
        decision.action = VideoSyncAction::kDrop;
        return decision;
    }
    if (delta_ms > 20) {
        decision.action = VideoSyncAction::kWait;
        decision.delay_ms = std::min<int64_t>(delta_ms, 60);
        return decision;
    }
    decision.action = VideoSyncAction::kRenderNow;
    return decision;
}

} // namespace player_sirius
