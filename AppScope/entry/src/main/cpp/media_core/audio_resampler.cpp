#include "audio_resampler.h"

#include <memory>

#if PLAYER_SIRIUS_HAS_FFMPEG
extern "C" {
#include <libavutil/channel_layout.h>
#include <libavutil/error.h>
#include <libavutil/frame.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>
}
#endif

namespace player_sirius {

struct AudioResampler::Impl {
#if PLAYER_SIRIUS_HAS_FFMPEG
    SwrContext* swr = nullptr;
    AVSampleFormat output_sample_format = AV_SAMPLE_FMT_S16;
#endif
    int output_sample_rate = 0;
    int output_channels = 0;
};

namespace {

std::string MakeErrorString(const std::string& prefix, int ffmpeg_error)
{
#if PLAYER_SIRIUS_HAS_FFMPEG
    char buffer[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_make_error_string(buffer, sizeof(buffer), ffmpeg_error);
    return prefix + ": " + buffer;
#else
    (void)ffmpeg_error;
    return prefix;
#endif
}

} // namespace

AudioResampler::AudioResampler()
    : impl_(new Impl())
{
}

AudioResampler::~AudioResampler()
{
    Reset();
    delete impl_;
    impl_ = nullptr;
}

bool AudioResampler::Configure(const MediaFrame& frame, std::string* error)
{
    if (!frame.audio || !frame.native_frame) {
        if (error != nullptr) {
            *error = "audio resampler requires decoded audio frame";
        }
        return false;
    }
#if !PLAYER_SIRIUS_HAS_FFMPEG
    if (error != nullptr) {
        *error = "FFmpeg audio resampler backend is not linked";
    }
    return false;
#else
    Reset();

    AVFrame* native_frame = static_cast<AVFrame*>(frame.native_frame.get());
    impl_->output_sample_rate = native_frame->sample_rate;
    impl_->output_channels = native_frame->ch_layout.nb_channels;
    int rc = swr_alloc_set_opts2(
        &impl_->swr,
        &native_frame->ch_layout,
        impl_->output_sample_format,
        native_frame->sample_rate,
        &native_frame->ch_layout,
        static_cast<AVSampleFormat>(native_frame->format),
        native_frame->sample_rate,
        0,
        nullptr);
    if (rc < 0 || impl_->swr == nullptr) {
        if (error != nullptr) {
            *error = MakeErrorString("swr_alloc_set_opts2 failed", rc);
        }
        Reset();
        return false;
    }

    rc = swr_init(impl_->swr);
    if (rc < 0) {
        if (error != nullptr) {
            *error = MakeErrorString("swr_init failed", rc);
        }
        Reset();
        return false;
    }
    return true;
#endif
}

bool AudioResampler::Convert(const MediaFrame& frame, AudioPcmBuffer* pcm, std::string* error)
{
    if (pcm == nullptr) {
        if (error != nullptr) {
            *error = "audio resampler output is null";
        }
        return false;
    }
    if (!frame.audio || !frame.native_frame) {
        if (error != nullptr) {
            *error = "audio resampler requires decoded audio frame";
        }
        return false;
    }
#if !PLAYER_SIRIUS_HAS_FFMPEG
    if (error != nullptr) {
        *error = "FFmpeg audio resampler backend is not linked";
    }
    return false;
#else
    if (impl_->swr == nullptr && !Configure(frame, error)) {
        return false;
    }

    AVFrame* native_frame = static_cast<AVFrame*>(frame.native_frame.get());
    const int dst_samples = swr_get_out_samples(impl_->swr, native_frame->nb_samples);
    if (dst_samples <= 0) {
        if (error != nullptr) {
            *error = "swr_get_out_samples returned non-positive result";
        }
        return false;
    }

    const int bytes_per_sample = av_get_bytes_per_sample(impl_->output_sample_format);
    const int output_channels = impl_->output_channels > 0 ? impl_->output_channels : native_frame->ch_layout.nb_channels;
    std::vector<uint8_t> interleaved(static_cast<size_t>(dst_samples * output_channels * bytes_per_sample), 0);
    uint8_t* output_data[1] = {interleaved.data()};
    const int converted_samples = swr_convert(
        impl_->swr,
        output_data,
        dst_samples,
        const_cast<const uint8_t**>(native_frame->extended_data),
        native_frame->nb_samples);
    if (converted_samples < 0) {
        if (error != nullptr) {
            *error = MakeErrorString("swr_convert failed", converted_samples);
        }
        return false;
    }

    const size_t converted_bytes = static_cast<size_t>(converted_samples * output_channels * bytes_per_sample);
    interleaved.resize(converted_bytes);
    pcm->sample_rate = impl_->output_sample_rate;
    pcm->channels = output_channels;
    pcm->bytes_per_sample = bytes_per_sample;
    pcm->samples_per_channel = converted_samples;
    pcm->data = std::move(interleaved);
    return true;
#endif
}

void AudioResampler::Reset()
{
#if PLAYER_SIRIUS_HAS_FFMPEG
    if (impl_ != nullptr && impl_->swr != nullptr) {
        swr_free(&impl_->swr);
    }
#endif
    if (impl_ != nullptr) {
        impl_->output_sample_rate = 0;
        impl_->output_channels = 0;
    }
}

} // namespace player_sirius
