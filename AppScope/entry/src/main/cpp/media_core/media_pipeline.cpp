#include "media_pipeline.h"

#include <algorithm>
#include <utility>

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
        Assign(error, source.surface_id.empty() ? "renderer surface is empty" : kRendererBlocker);
        return false;
    }

    bool Render(const MediaFrame& frame, std::string* error) override
    {
        last_pts_ms_ = frame.pts_ms;
        Assign(error, kRendererBlocker);
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

class SimpleClock final : public Clock {
public:
    const char* Name() const override
    {
        return "simple-clock";
    }

    void Reset() override
    {
        running_ = false;
        position_ms_ = 0;
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
        position_ms_ = std::max<int64_t>(0, position_ms);
    }

    int64_t PositionMs() const override
    {
        return position_ms_;
    }

private:
    bool running_ = false;
    int64_t position_ms_ = 0;
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

MediaPipeline::~MediaPipeline() = default;

bool MediaPipeline::Prepare(const SourceSpec& source, std::string* error)
{
    source_ = source;
    prepared_ = false;
    playing_ = false;
    if (stats_collector_) {
        stats_collector_->Reset();
    }
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
    clock_->Start();
    if (stats_collector_) {
        stats_collector_->OnPlay();
        stats_collector_->OnBufferedDuration(250);
    }
    playing_ = true;
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
    playing_ = false;
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
    playing_ = false;
    prepared_ = false;
    clock_->Reset();
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
    clock_->Seek(position_ms);
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
    playing_ = false;
    prepared_ = false;
    clock_->Reset();
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
    stage_ = stage;
    if (stats_collector_) {
        stats_collector_->OnStageChanged(stage);
    }
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
    return std::make_unique<PlaceholderDemuxer>();
}

std::unique_ptr<Decoder> CreateDefaultDecoder()
{
    return std::make_unique<PlaceholderDecoder>();
}

std::unique_ptr<Renderer> CreateDefaultRenderer()
{
    return std::make_unique<PlaceholderRenderer>();
}

std::unique_ptr<Clock> CreateDefaultClock()
{
    return std::make_unique<SimpleClock>();
}

} // namespace player_sirius
