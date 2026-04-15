#include "soft_backend.h"

#include <algorithm>

namespace player_sirius {

namespace {

constexpr const char* kSoftBackendVersion = "0.3.1-p0";

#if PLAYER_SIRIUS_HAS_FFMPEG
constexpr const char* kBackendName = "ffmpeg-linked";
constexpr const char* kBlockerMessage = "FFmpeg detected, but decode/render pipeline is not implemented yet";
#else
constexpr const char* kBackendName = "ffmpeg-placeholder";
constexpr const char* kBlockerMessage = "FFmpeg backend not linked into current repository";
#endif

class UnavailableSoftDecodeBackend final : public SoftDecodeBackend {
public:
    Capability GetCapability() const override
    {
        Capability capability;
        capability.available = false;
        capability.version = kSoftBackendVersion;
        capability.features = {
            "soft-demux-interface",
            "soft-decoder-interface",
            "render-interface",
            "av-sync-interface",
            "event-bridge",
            "cmake-ffmpeg-probe",
            "pipeline-stage-reporting",
        };
        capability.backend_name = kBackendName;
        capability.blocker = kBlockerMessage;
        capability.stage = pipeline_->Stage();
        return capability;
    }

    std::string GetStage() const override
    {
        return pipeline_->Stage();
    }

    PlaybackMetrics GetMetrics() const override
    {
        return pipeline_->Metrics();
    }

    bool Prepare(const SourceSpec& source, std::string* error) override
    {
        source_ = source;
        if (source.source.empty()) {
            SetError(error, "prepare requires non-empty source");
            return false;
        }
        return pipeline_->Prepare(source, error);
    }

    bool Play(std::string* error) override
    {
        return pipeline_->Play(error);
    }

    bool Pause(std::string* error) override
    {
        return pipeline_->Pause(error);
    }

    bool Stop(std::string* error) override
    {
        last_position_ms_ = 0;
        return pipeline_->Stop(error);
    }

    bool Seek(int64_t position_ms, std::string* error) override
    {
        last_position_ms_ = std::max<int64_t>(0, position_ms);
        return pipeline_->Seek(position_ms, error);
    }

    void Release() override
    {
        source_ = SourceSpec();
        last_position_ms_ = 0;
        pipeline_->Release();
    }

private:
    UnavailableSoftDecodeBackend()
        : pipeline_(CreateDefaultMediaPipeline())
    {
    }

    static void SetError(std::string* error, const std::string& value)
    {
        if (error != nullptr) {
            *error = value;
        }
    }

    SourceSpec source_;
    int64_t last_position_ms_ = 0;
    std::unique_ptr<MediaPipeline> pipeline_;

    friend std::unique_ptr<SoftDecodeBackend> CreateSoftDecodeBackend();
};

} // namespace

std::unique_ptr<SoftDecodeBackend> CreateSoftDecodeBackend()
{
    return std::unique_ptr<SoftDecodeBackend>(new UnavailableSoftDecodeBackend());
}

} // namespace player_sirius
