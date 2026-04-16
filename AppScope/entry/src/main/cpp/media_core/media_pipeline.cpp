#include "media_pipeline.h"

#include <algorithm>
#include <chrono>
#include <utility>

#include "ffmpeg_decoder.h"
#include "ffmpeg_demuxer.h"
#include "video_converter.h"

namespace player_sirius {

namespace {

#if PLAYER_SIRIUS_HAS_FFMPEG
constexpr const char* kDemuxerBlocker = "FFmpeg demuxer detected, but avformat input stage is not implemented yet";
constexpr const char* kDecoderBlocker = "FFmpeg decoder stage is not implemented yet";
constexpr const char* kRendererBlocker = "Native renderer stage is not implemented yet";
#else
constexpr const char* kDemuxerBlocker = "FFmpeg demuxer backend is not linked";
constexpr const char* kDecoderBlocker = "FFmpeg decoder backend is not linked";
constexpr const char* kRendererBlocker = "Native renderer backend is not linked";
#endif

class PlaceholderDemuxer final : public Demuxer {
public:
    const char* Name() const override
    {
        return "placeholder-demuxer";
    }

    bool Open(const SourceSpec& source, std::string* error) override
    {
        source_ = source;
        if (source.source.empty()) {
            Assign(error, "source is empty");
            return false;
        }
        Assign(error, kDemuxerBlocker);
        return false;
    }

    bool ReadPacket(MediaPacket* packet, std::string* error) override
    {
        (void)packet;
        Assign(error, kDemuxerBlocker);
        return false;
    }

    bool Seek(int64_t position_ms, std::string* error) override
    {
        position_ms_ = std::max<int64_t>(0, position_ms);
        Assign(error, kDemuxerBlocker);
        return false;
    }

    const MediaStreamInfo* GetPrimaryAudioStream() const override
    {
        return nullptr;
    }

    const MediaStreamInfo* GetPrimaryVideoStream() const override
    {
        return nullptr;
    }

    void Close() override
    {
        source_ = SourceSpec();
        position_ms_ = 0;
    }

private:
    static void Assign(std::string* error, const std::string& message)
    {
        if (error != nullptr) {
            *error = message;
        }
    }

    SourceSpec source_;
    int64_t position_ms_ = 0;
};

class PlaceholderDecoder final : public Decoder {
public:
    const char* Name() const override
    {
        return "placeholder-decoder";
    }

    bool Configure(const Demuxer& demuxer, std::string* error) override
    {
        demuxer_name_ = demuxer.Name();
        Assign(error, kDecoderBlocker);
        return false;
    }

    bool Decode(const MediaPacket& packet, MediaFrame* frame, std::string* error) override
    {
        last_pts_ms_ = packet.pts_ms;
        (void)frame;
        Assign(error, kDecoderBlocker);
        return false;
    }

    bool Drain(MediaFrame* frame, std::string* error) override
    {
        (void)frame;
        Assign(error, kDecoderBlocker);
        return false;
    }

    void Flush() override
    {
        last_pts_ms_ = 0;
    }

    void Close() override
    {
        demuxer_name_.clear();
        last_pts_ms_ = 0;
    }

private:
    static void Assign(std::string* error, const std::string& message)
    {
        if (error != nullptr) {
            *error = message;
        }
    }

    std::string demuxer_name_;
    int64_t last_pts_ms_ = 0;
};

class PlaceholderRenderer final : public Renderer {
public:
    const char* Name() const override
    {
        return "placeholder-renderer";
    }

    bool Configure(const SourceSpec& source, std::string* error) override
    {
        source_ = source;
#if PLAYER_SIRIUS_HAS_FFMPEG
        if (source.source.empty()) {
            Assign(error, "renderer source is empty");
            return false;
        }
        last_buffer_ = VideoPixelBuffer();
        return true;
#else
        Assign(error, source.surface_id.empty() ? "renderer surface is empty" : kRendererBlocker);
        return false;
#endif
    }

    bool Render(const MediaFrame& frame, std::string* error) override
    {
        last_pts_ms_ = frame.pts_ms;
#if PLAYER_SIRIUS_HAS_FFMPEG
        if (!frame.video) {
            return true;
        }
        return converter_.Convert(frame, &last_buffer_, error);
#else
        Assign(error, kRendererBlocker);
        return false;
#endif
    }

    void Reset() override
    {
        last_pts_ms_ = 0;
        last_buffer_ = VideoPixelBuffer();
        converter_.Reset();
    }

    void Close() override
    {
        source_ = SourceSpec();
        last_pts_ms_ = 0;
        last_buffer_ = VideoPixelBuffer();
        converter_.Reset();
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
    VideoConverter converter_;
    VideoPixelBuffer last_buffer_;
};

class SimpleClock final : public Clock {
public:
    const char* Name() const override
    {
        return "simple-clock";
    }

    void Reset() override
    {
        running_ = false;
        position_ms_.store(0);
    }

    void Start() override
    {
        running_ = true;
    }

    void Pause() override
    {
        running_ = false;
    }

    void Seek(int64_t position_ms) override
    {
        position_ms_.store(std::max<int64_t>(0, position_ms));
    }

    int64_t PositionMs() const override
    {
        return position_ms_.load();
    }

private:
    bool running_ = false;
    std::atomic<int64_t> position_ms_{0};
};

} // namespace

MediaPipeline::MediaPipeline(
    std::unique_ptr<Demuxer> demuxer,
    std::unique_ptr<Decoder> decoder,
    std::unique_ptr<Renderer> renderer,
    std::unique_ptr<AudioOutput> audio_output,
    std::unique_ptr<Clock> clock,
    std::unique_ptr<PlaybackStatsCollector> stats_collector)
    : demuxer_(std::move(demuxer)),
      decoder_(std::move(decoder)),
      renderer_(std::move(renderer)),
      audio_output_(std::move(audio_output)),
      clock_(std::move(clock)),
      stats_collector_(std::move(stats_collector))
{
}

MediaPipeline::~MediaPipeline()
{
    // Ensure worker thread and platform outputs are released even if caller forgets to call Release().
    Release();
}

bool MediaPipeline::Prepare(const SourceSpec& source, std::string* error)
{
    StopPlaybackWorker();
    source_ = source;
    prepared_ = false;
    playing_.store(false);
    stop_requested_.store(false);
    end_of_stream_.store(false);
    decoder_drained_.store(false);
    packet_queue_.Reopen();
    audio_frame_queue_.Reopen();
    video_frame_queue_.Reopen();
    packet_queue_.Clear();
    audio_frame_queue_.Clear();
    video_frame_queue_.Clear();
    if (stats_collector_) {
        stats_collector_->Reset();
    }
    sync_controller_.Reset();
    SetStage("input");
    if (source.source.empty()) {
        if (error != nullptr) {
            *error = "prepare requires non-empty source";
        }
        return false;
    }

    SetStage("demuxer");
    if (!demuxer_->Open(source, error)) {
        return false;
    }

    SetStage("decoder");
    if (!decoder_->Configure(*demuxer_, error)) {
        demuxer_->Close();
        return false;
    }

    SetStage("renderer");
    if (!renderer_->Configure(source, error)) {
        decoder_->Close();
        demuxer_->Close();
        return false;
    }

    SetStage("audio-output");
    if (!audio_output_->Configure(source, error)) {
        renderer_->Close();
        decoder_->Close();
        demuxer_->Close();
        return false;
    }

    clock_->Reset();
    if (stats_collector_) {
        stats_collector_->OnPrepared(source);
        stats_collector_->OnBufferedDuration(0);
        stats_collector_->OnQueueDepths(0, 0, 0);
        stats_collector_->OnAudioClock(0);
        stats_collector_->OnVideoClock(0);
    }
    prepared_ = true;
    SetStage("prepared");
    return true;
}

bool MediaPipeline::Play(std::string* error)
{
    if (!prepared_) {
        if (error != nullptr) {
            *error = "play requires prepared pipeline";
        }
        return false;
    }
    if (!StartPlaybackWorker(error)) {
        return false;
    }
    clock_->Start();
    if (stats_collector_) {
        stats_collector_->OnPlay();
    }
    playing_.store(true);
    playback_condition_.notify_all();
    SetStage("playback-loop");
    return true;
}

bool MediaPipeline::Pause(std::string* error)
{
    if (!playing_) {
        if (error != nullptr) {
            *error = "pause requires active playback loop";
        }
        return false;
    }
    clock_->Pause();
    if (stats_collector_) {
        stats_collector_->OnPause();
    }
    playing_.store(false);
    SetStage("paused");
    return true;
}

bool MediaPipeline::Stop(std::string* error)
{
    if (!prepared_ && !playing_) {
        if (error != nullptr) {
            *error = "stop requires prepared pipeline";
        }
        return false;
    }
    playing_.store(false);
    prepared_ = false;
    StopPlaybackWorker();
    clock_->Reset();
    sync_controller_.Reset();
    renderer_->Reset();
    audio_output_->Reset();
    decoder_->Flush();
    audio_output_->Close();
    renderer_->Close();
    decoder_->Close();
    demuxer_->Close();
    SetStage("stopped");
    return true;
}

bool MediaPipeline::Seek(int64_t position_ms, std::string* error)
{
    if (!prepared_ && !playing_) {
        if (error != nullptr) {
            *error = "seek requires prepared pipeline";
        }
        return false;
    }
    SetStage("seek");
    if (!demuxer_->Seek(position_ms, error)) {
        return false;
    }
    packet_queue_.Clear();
    audio_frame_queue_.Clear();
    video_frame_queue_.Clear();
    end_of_stream_.store(false);
    clock_->Seek(position_ms);
    sync_controller_.OnSeek(position_ms);
    decoder_->Flush();
    audio_output_->Reset();
    if (stats_collector_) {
        stats_collector_->OnSeek(position_ms);
    }
    SetStage(playing_ ? "playback-loop" : "paused");
    return true;
}

void MediaPipeline::Release()
{
    playing_.store(false);
    prepared_ = false;
    StopPlaybackWorker();
    clock_->Reset();
    sync_controller_.Reset();
    renderer_->Reset();
    audio_output_->Reset();
    audio_output_->Close();
    renderer_->Close();
    decoder_->Flush();
    decoder_->Close();
    demuxer_->Close();
    if (stats_collector_) {
        stats_collector_->Reset();
    }
    source_ = SourceSpec();
    SetStage("idle");
}

std::string MediaPipeline::Stage() const
{
    std::lock_guard<std::mutex> lock(stage_mutex_);
    return stage_;
}

PlaybackMetrics MediaPipeline::Metrics() const
{
    if (!stats_collector_) {
        return PlaybackMetrics();
    }
    return stats_collector_->Snapshot();
}

void MediaPipeline::SetStage(const std::string& stage)
{
    {
        std::lock_guard<std::mutex> lock(stage_mutex_);
        stage_ = stage;
    }
    if (stats_collector_) {
        stats_collector_->OnStageChanged(stage);
    }
}

bool MediaPipeline::StartPlaybackWorker(std::string* error)
{
    if (playback_thread_.joinable()) {
        return true;
    }
    stop_requested_.store(false);
    end_of_stream_.store(false);
    decoder_drained_.store(false);
    try {
        playback_thread_ = std::thread(&MediaPipeline::PlaybackLoop, this);
        return true;
    } catch (const std::exception& exception) {
        if (error != nullptr) {
            *error = std::string("failed to start playback worker: ") + exception.what();
        }
        return false;
    } catch (...) {
        if (error != nullptr) {
            *error = "failed to start playback worker";
        }
        return false;
    }
}

void MediaPipeline::StopPlaybackWorker()
{
    stop_requested_.store(true);
    playing_.store(false);
    packet_queue_.Close();
    audio_frame_queue_.Close();
    video_frame_queue_.Close();
    playback_condition_.notify_all();
    if (playback_thread_.joinable()) {
        playback_thread_.join();
    }
    packet_queue_.Reopen();
    audio_frame_queue_.Reopen();
    video_frame_queue_.Reopen();
}

void MediaPipeline::PlaybackLoop()
{
    while (!stop_requested_.load()) {
        if (!playing_.load()) {
            std::unique_lock<std::mutex> lock(state_mutex_);
            playback_condition_.wait_for(lock, std::chrono::milliseconds(20), [this]() {
                return stop_requested_.load() || playing_.load();
            });
            continue;
        }

        std::string error;
        if (!FillPacketQueue(&error) || !DecodePacketIntoFrames(&error) || !DrainDecoderFrames(&error) || !DrainFrameQueues(&error)) {
            if (!error.empty()) {
                SetStage("error");
            }
            playing_.store(false);
            break;
        }

        if (stats_collector_) {
            stats_collector_->OnBufferedDuration(EstimateBufferedDurationMs());
            stats_collector_->OnQueueDepths(
                static_cast<int64_t>(packet_queue_.Size()),
                static_cast<int64_t>(audio_frame_queue_.Size()),
                static_cast<int64_t>(video_frame_queue_.Size()));
            stats_collector_->OnAudioClock(sync_controller_.MasterClockMs());
        }

        if (end_of_stream_.load() && decoder_drained_.load() &&
            packet_queue_.Empty() && audio_frame_queue_.Empty() && video_frame_queue_.Empty()) {
            playing_.store(false);
            clock_->Pause();
            SetStage("drained");
            break;
        }
    }
}

bool MediaPipeline::FillPacketQueue(std::string* error)
{
    while (packet_queue_.Size() < 8 && !end_of_stream_.load() && !stop_requested_.load() && playing_.load()) {
        MediaPacket packet;
        if (!demuxer_->ReadPacket(&packet, error)) {
            return false;
        }
        if (packet.end_of_stream) {
            end_of_stream_.store(true);
            break;
        }
        if (!packet.audio && !packet.video) {
            continue;
        }
        packet_queue_.Push(std::move(packet));
    }
    return true;
}

bool MediaPipeline::DecodePacketIntoFrames(std::string* error)
{
    MediaPacket packet;
    if (!packet_queue_.Pop(&packet, std::chrono::milliseconds(1))) {
        return true;
    }
    MediaFrame frame;
    if (!decoder_->Decode(packet, &frame, error)) {
        return false;
    }
    if (!frame.audio && !frame.video) {
        return true;
    }
    if (stats_collector_) {
        stats_collector_->OnDecodeFrame(frame.audio, frame.video);
    }
    if (frame.audio) {
        audio_frame_queue_.Push(std::move(frame));
    } else if (frame.video) {
        video_frame_queue_.Push(std::move(frame));
    }
    return true;
}

bool MediaPipeline::DrainDecoderFrames(std::string* error)
{
    if (!end_of_stream_.load() || decoder_drained_.load()) {
        return true;
    }
    MediaFrame frame;
    if (!decoder_->Drain(&frame, error)) {
        return false;
    }
    if (!frame.audio && !frame.video) {
        decoder_drained_.store(true);
        return true;
    }
    if (stats_collector_) {
        stats_collector_->OnDecodeFrame(frame.audio, frame.video);
    }
    if (frame.audio) {
        audio_frame_queue_.Push(std::move(frame));
    } else if (frame.video) {
        video_frame_queue_.Push(std::move(frame));
    }
    return true;
}

bool MediaPipeline::DrainFrameQueues(std::string* error)
{
    MediaFrame audio_frame;
    if (audio_frame_queue_.Pop(&audio_frame, std::chrono::milliseconds(0))) {
        if (!audio_output_->Submit(audio_frame, error)) {
            return false;
        }
        clock_->Seek(audio_frame.pts_ms);
        sync_controller_.OnAudioRendered(audio_frame.pts_ms);
        if (stats_collector_) {
            stats_collector_->OnRenderFrame(true, false);
            stats_collector_->OnAudioClock(audio_frame.pts_ms);
        }
    }

    MediaFrame video_frame;
    if (video_frame_queue_.Pop(&video_frame, std::chrono::milliseconds(0))) {
        const VideoSyncDecision decision = sync_controller_.DecideVideoFrame(video_frame.pts_ms, clock_->PositionMs());
        if (decision.action == VideoSyncAction::kDrop) {
            if (stats_collector_) {
                stats_collector_->OnDropVideoFrame();
            }
            return true;
        }
        if (decision.action == VideoSyncAction::kWait && decision.delay_ms > 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(decision.delay_ms));
        }
        if (!renderer_->Render(video_frame, error)) {
            return false;
        }
        sync_controller_.OnVideoRendered(video_frame.pts_ms);
        if (stats_collector_) {
            stats_collector_->OnRenderFrame(false, true);
            stats_collector_->OnVideoClock(video_frame.pts_ms);
        }
        if (audio_frame_queue_.Empty()) {
            clock_->Seek(video_frame.pts_ms);
        }
    }
    return true;
}

int64_t MediaPipeline::EstimateBufferedDurationMs() const
{
    return static_cast<int64_t>((audio_frame_queue_.Size() + video_frame_queue_.Size()) * 20);
}

std::unique_ptr<MediaPipeline> CreateDefaultMediaPipeline()
{
    return std::make_unique<MediaPipeline>(
        CreateDefaultDemuxer(),
        CreateDefaultDecoder(),
        CreateDefaultRenderer(),
        CreateDefaultAudioOutput(),
        CreateDefaultClock(),
        CreateDefaultStatsCollector());
}

std::unique_ptr<Demuxer> CreateDefaultDemuxer()
{
#if PLAYER_SIRIUS_HAS_FFMPEG
    return std::make_unique<FfmpegDemuxer>();
#else
    return std::make_unique<PlaceholderDemuxer>();
#endif
}

std::unique_ptr<Decoder> CreateDefaultDecoder()
{
#if PLAYER_SIRIUS_HAS_FFMPEG
    return std::make_unique<FfmpegDecoder>();
#else
    return std::make_unique<PlaceholderDecoder>();
#endif
}

std::unique_ptr<Renderer> CreateDefaultRenderer()
{
    if (auto platform_renderer = CreatePlatformRenderer()) {
        return platform_renderer;
    }
    return std::make_unique<PlaceholderRenderer>();
}

std::unique_ptr<Clock> CreateDefaultClock()
{
    return std::make_unique<SimpleClock>();
}

} // namespace player_sirius
