#include "platform_outputs.h"

#include <algorithm>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <string>

#include "audio_resampler.h"

#if PLAYER_SIRIUS_HAS_OH_AUDIO
#include <ohaudio/native_audiorenderer.h>
#include <ohaudio/native_audiostream_base.h>
#include <ohaudio/native_audiostreambuilder.h>
#endif

namespace player_sirius {

#if PLAYER_SIRIUS_HAS_OH_AUDIO
namespace {

OH_AudioStream_SampleFormat ToOhSampleFormat(int bytes_per_sample)
{
    return bytes_per_sample == 2 ? AUDIOSTREAM_SAMPLE_S16LE : AUDIOSTREAM_SAMPLE_S32LE;
}

class HarmonyAudioOutput final : public AudioOutput {
public:
    const char* Name() const override
    {
        return "harmony-ohaudio-output";
    }

    bool Configure(const SourceSpec& source, std::string* error) override
    {
        source_ = source;
        CloseRenderer();
        return true;
    }

    bool Submit(const MediaFrame& frame, std::string* error) override
    {
        if (!frame.audio) {
            return true;
        }
        AudioPcmBuffer pcm;
        if (!resampler_.Convert(frame, &pcm, error)) {
            return false;
        }
        if (!EnsureRenderer(pcm, error)) {
            return false;
        }
        {
            std::lock_guard<std::mutex> lock(buffer_mutex_);
            pcm_buffer_.insert(pcm_buffer_.end(), pcm.data.begin(), pcm.data.end());
        }
        return true;
    }

    void Reset() override
    {
        std::lock_guard<std::mutex> lock(buffer_mutex_);
        pcm_buffer_.clear();
        resampler_.Reset();
        if (renderer_ != nullptr) {
            OH_AudioRenderer_Flush(renderer_);
        }
    }

    void Close() override
    {
        {
            std::lock_guard<std::mutex> lock(buffer_mutex_);
            pcm_buffer_.clear();
        }
        resampler_.Reset();
        source_ = SourceSpec();
        CloseRenderer();
    }

private:
    static OH_AudioData_Callback_Result OnWriteData(
        OH_AudioRenderer* renderer,
        void* user_data,
        void* audio_data,
        int32_t audio_data_size)
    {
        (void)renderer;
        auto* self = static_cast<HarmonyAudioOutput*>(user_data);
        if (self == nullptr || audio_data == nullptr || audio_data_size <= 0) {
            return AUDIO_DATA_CALLBACK_RESULT_INVALID;
        }
        std::lock_guard<std::mutex> lock(self->buffer_mutex_);
        auto* destination = static_cast<uint8_t*>(audio_data);
        std::memset(destination, 0, static_cast<size_t>(audio_data_size));
        const int32_t available = static_cast<int32_t>(self->pcm_buffer_.size());
        const int32_t to_copy = std::min(available, audio_data_size);
        for (int32_t index = 0; index < to_copy; ++index) {
            destination[index] = self->pcm_buffer_.front();
            self->pcm_buffer_.pop_front();
        }
        return AUDIO_DATA_CALLBACK_RESULT_VALID;
    }

    static void OnInterrupt(
        OH_AudioRenderer* renderer,
        void* user_data,
        OH_AudioInterrupt_ForceType type,
        OH_AudioInterrupt_Hint hint)
    {
        (void)type;
        auto* self = static_cast<HarmonyAudioOutput*>(user_data);
        if (renderer == nullptr || self == nullptr) {
            return;
        }
        if (hint == AUDIOSTREAM_INTERRUPT_HINT_PAUSE) {
            OH_AudioRenderer_Pause(renderer);
        } else if (hint == AUDIOSTREAM_INTERRUPT_HINT_STOP) {
            OH_AudioRenderer_Stop(renderer);
        }
    }

    static void OnError(OH_AudioRenderer* renderer, void* user_data, OH_AudioStream_Result error)
    {
        (void)renderer;
        auto* self = static_cast<HarmonyAudioOutput*>(user_data);
        if (self == nullptr) {
            return;
        }
        std::lock_guard<std::mutex> lock(self->buffer_mutex_);
        self->last_error_ = std::to_string(static_cast<int>(error));
    }

    bool EnsureRenderer(const AudioPcmBuffer& pcm, std::string* error)
    {
        if (renderer_ != nullptr &&
            sample_rate_ == pcm.sample_rate &&
            channels_ == pcm.channels &&
            bytes_per_sample_ == pcm.bytes_per_sample) {
            return true;
        }

        CloseRenderer();
        sample_rate_ = pcm.sample_rate;
        channels_ = pcm.channels;
        bytes_per_sample_ = pcm.bytes_per_sample;

        OH_AudioStreamBuilder* builder = nullptr;
        if (OH_AudioStreamBuilder_Create(&builder, AUDIOSTREAM_TYPE_RENDERER) != AUDIOSTREAM_SUCCESS || builder == nullptr) {
            if (error != nullptr) {
                *error = "OH_AudioStreamBuilder_Create failed";
            }
            return false;
        }

        OH_AudioStreamBuilder_SetSamplingRate(builder, sample_rate_);
        OH_AudioStreamBuilder_SetChannelCount(builder, channels_);
        OH_AudioStreamBuilder_SetSampleFormat(builder, ToOhSampleFormat(bytes_per_sample_));
        OH_AudioStreamBuilder_SetEncodingType(builder, AUDIOSTREAM_ENCODING_TYPE_RAW);
        OH_AudioStreamBuilder_SetRendererInfo(builder, AUDIOSTREAM_USAGE_MUSIC);
        OH_AudioStreamBuilder_SetFrameSizeInCallback(builder, 2048);
        OH_AudioStreamBuilder_SetRendererWriteDataCallback(builder, &HarmonyAudioOutput::OnWriteData, this);
        OH_AudioStreamBuilder_SetRendererInterruptCallback(builder, &HarmonyAudioOutput::OnInterrupt, this);
        OH_AudioStreamBuilder_SetRendererErrorCallback(builder, &HarmonyAudioOutput::OnError, this);

        if (OH_AudioStreamBuilder_GenerateRenderer(builder, &renderer_) != AUDIOSTREAM_SUCCESS || renderer_ == nullptr) {
            OH_AudioStreamBuilder_Destroy(builder);
            if (error != nullptr) {
                *error = "OH_AudioStreamBuilder_GenerateRenderer failed";
            }
            return false;
        }
        OH_AudioStreamBuilder_Destroy(builder);

        if (OH_AudioRenderer_Start(renderer_) != AUDIOSTREAM_SUCCESS) {
            if (error != nullptr) {
                *error = "OH_AudioRenderer_Start failed";
            }
            CloseRenderer();
            return false;
        }
        return true;
    }

    void CloseRenderer()
    {
        if (renderer_ != nullptr) {
            OH_AudioRenderer_Stop(renderer_);
            OH_AudioRenderer_Release(renderer_);
            renderer_ = nullptr;
        }
        sample_rate_ = 0;
        channels_ = 0;
        bytes_per_sample_ = 0;
        last_error_.clear();
    }

    SourceSpec source_;
    AudioResampler resampler_;
    std::mutex buffer_mutex_;
    std::deque<uint8_t> pcm_buffer_;
    std::string last_error_;
    OH_AudioRenderer* renderer_ = nullptr;
    int sample_rate_ = 0;
    int channels_ = 0;
    int bytes_per_sample_ = 0;
};

} // namespace
#endif

std::unique_ptr<AudioOutput> CreatePlatformAudioOutput()
{
#if PLAYER_SIRIUS_HAS_OH_AUDIO
    return std::make_unique<HarmonyAudioOutput>();
#else
    return nullptr;
#endif
}

} // namespace player_sirius
