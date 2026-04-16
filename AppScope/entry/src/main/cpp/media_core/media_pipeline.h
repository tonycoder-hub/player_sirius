#pragma once

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "media_queue.h"
#include "platform_outputs.h"
#include "pipeline_components.h"
#include "sync_controller.h"

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
    bool StartPlaybackWorker(std::string* error);
    void StopPlaybackWorker();
    void PlaybackLoop();
    bool FillPacketQueue(std::string* error);
    bool DecodePacketIntoFrames(std::string* error);
    bool DrainDecoderFrames(std::string* error);
    bool DrainFrameQueues(std::string* error);
    int64_t EstimateBufferedDurationMs() const;

    std::unique_ptr<Demuxer> demuxer_;
    std::unique_ptr<Decoder> decoder_;
    std::unique_ptr<Renderer> renderer_;
    std::unique_ptr<AudioOutput> audio_output_;
    std::unique_ptr<Clock> clock_;
    std::unique_ptr<PlaybackStatsCollector> stats_collector_;
    MediaQueue<MediaPacket> packet_queue_{48};
    MediaQueue<MediaFrame> audio_frame_queue_{48};
    MediaQueue<MediaFrame> video_frame_queue_{48};
    SyncController sync_controller_;
    SourceSpec source_;
    mutable std::mutex stage_mutex_;
    std::string stage_ = "idle";
    bool prepared_ = false;
    std::atomic<bool> playing_{false};
    std::atomic<bool> stop_requested_{false};
    std::atomic<bool> end_of_stream_{false};
    std::atomic<bool> decoder_drained_{false};
    mutable std::mutex state_mutex_;
    std::condition_variable playback_condition_;
    std::thread playback_thread_;
};

std::unique_ptr<MediaPipeline> CreateDefaultMediaPipeline();

} // namespace player_sirius
