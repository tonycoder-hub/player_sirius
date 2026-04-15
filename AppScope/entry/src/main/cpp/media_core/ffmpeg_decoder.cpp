#include "ffmpeg_decoder.h"

#include <memory>

#include "ffmpeg_demuxer.h"

#if PLAYER_SIRIUS_HAS_FFMPEG
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/channel_layout.h>
#include <libavutil/error.h>
#include <libavutil/frame.h>
#include <libavutil/rational.h>
}
#endif

namespace player_sirius {

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

#if PLAYER_SIRIUS_HAS_FFMPEG
int64_t ToMilliseconds(int64_t value, AVRational time_base)
{
    if (value == AV_NOPTS_VALUE) {
        return 0;
    }
    return av_rescale_q(value, time_base, AVRational{1, 1000});
}

AVCodecContext* OpenCodecContext(AVStream* stream, std::string* error)
{
    if (stream == nullptr || stream->codecpar == nullptr) {
        if (error != nullptr) {
            *error = "FFmpeg stream parameters are unavailable";
        }
        return nullptr;
    }
    const AVCodec* codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (codec == nullptr) {
        if (error != nullptr) {
            *error = "avcodec_find_decoder failed";
        }
        return nullptr;
    }

    AVCodecContext* context = avcodec_alloc_context3(codec);
    if (context == nullptr) {
        if (error != nullptr) {
            *error = "avcodec_alloc_context3 failed";
        }
        return nullptr;
    }

    int rc = avcodec_parameters_to_context(context, stream->codecpar);
    if (rc < 0) {
        if (error != nullptr) {
            *error = MakeErrorString("avcodec_parameters_to_context failed", rc);
        }
        avcodec_free_context(&context);
        return nullptr;
    }

    rc = avcodec_open2(context, codec, nullptr);
    if (rc < 0) {
        if (error != nullptr) {
            *error = MakeErrorString("avcodec_open2 failed", rc);
        }
        avcodec_free_context(&context);
        return nullptr;
    }
    return context;
}
#endif

} // namespace

FfmpegDecoder::FfmpegDecoder() = default;

FfmpegDecoder::~FfmpegDecoder()
{
    Close();
}

const char* FfmpegDecoder::Name() const
{
    return "ffmpeg-decoder";
}

bool FfmpegDecoder::Configure(const Demuxer& demuxer, std::string* error)
{
#if !PLAYER_SIRIUS_HAS_FFMPEG
    (void)demuxer;
    if (error != nullptr) {
        *error = "FFmpeg decoder backend is not linked";
    }
    return false;
#else
    Close();
    if (!OpenAudioDecoder(demuxer, error)) {
        Close();
        return false;
    }
    if (!OpenVideoDecoder(demuxer, error)) {
        Close();
        return false;
    }
    if (audio_codec_context_ == nullptr && video_codec_context_ == nullptr) {
        if (error != nullptr) {
            *error = "no audio/video decoder could be configured";
        }
        return false;
    }
    audio_drain_started_ = false;
    video_drain_started_ = false;
    audio_drain_finished_ = audio_codec_context_ == nullptr;
    video_drain_finished_ = video_codec_context_ == nullptr;
    return true;
#endif
}

bool FfmpegDecoder::Decode(const MediaPacket& packet, MediaFrame* frame, std::string* error)
{
    if (frame == nullptr) {
        if (error != nullptr) {
            *error = "decoder frame output is null";
        }
        return false;
    }
#if !PLAYER_SIRIUS_HAS_FFMPEG
    (void)packet;
    if (error != nullptr) {
        *error = "FFmpeg decoder backend is not linked";
    }
    return false;
#else
    if (packet.end_of_stream) {
        *frame = MediaFrame();
        return true;
    }
    if (!packet.native_packet) {
        if (error != nullptr) {
            *error = "decoder packet native handle is missing";
        }
        return false;
    }

    AVPacket* native_packet = static_cast<AVPacket*>(packet.native_packet.get());
    AVCodecContext* context = packet.audio ? audio_codec_context_ : video_codec_context_;
    if (context == nullptr) {
        if (error != nullptr) {
            *error = packet.audio ? "audio decoder is not configured" : "video decoder is not configured";
        }
        return false;
    }

    const int send_rc = avcodec_send_packet(context, native_packet);
    if (send_rc < 0) {
        if (error != nullptr) {
            *error = MakeErrorString("avcodec_send_packet failed", send_rc);
        }
        return false;
    }

    if (packet.audio) {
        audio_drain_started_ = false;
        audio_drain_finished_ = false;
    } else if (packet.video) {
        video_drain_started_ = false;
        video_drain_finished_ = false;
    }

    return ReceiveFrame(context, packet.audio, packet.video, frame, error);
#endif
}

bool FfmpegDecoder::Drain(MediaFrame* frame, std::string* error)
{
    if (frame == nullptr) {
        if (error != nullptr) {
            *error = "decoder drain frame output is null";
        }
        return false;
    }
#if !PLAYER_SIRIUS_HAS_FFMPEG
    if (error != nullptr) {
        *error = "FFmpeg decoder backend is not linked";
    }
    return false;
#else
    *frame = MediaFrame();
    if (!audio_drain_finished_ && audio_codec_context_ != nullptr) {
        return DrainContext(audio_codec_context_, &audio_drain_started_, &audio_drain_finished_, true, false, frame, error);
    }
    if (!video_drain_finished_ && video_codec_context_ != nullptr) {
        return DrainContext(video_codec_context_, &video_drain_started_, &video_drain_finished_, false, true, frame, error);
    }
    return true;
#endif
}

void FfmpegDecoder::Flush()
{
#if PLAYER_SIRIUS_HAS_FFMPEG
    if (audio_codec_context_ != nullptr) {
        avcodec_flush_buffers(audio_codec_context_);
    }
    if (video_codec_context_ != nullptr) {
        avcodec_flush_buffers(video_codec_context_);
    }
    audio_drain_started_ = false;
    video_drain_started_ = false;
    audio_drain_finished_ = audio_codec_context_ == nullptr;
    video_drain_finished_ = video_codec_context_ == nullptr;
#endif
}

void FfmpegDecoder::Close()
{
#if PLAYER_SIRIUS_HAS_FFMPEG
    if (audio_codec_context_ != nullptr) {
        avcodec_free_context(&audio_codec_context_);
    }
    if (video_codec_context_ != nullptr) {
        avcodec_free_context(&video_codec_context_);
    }
#endif
    audio_codec_context_ = nullptr;
    video_codec_context_ = nullptr;
    audio_drain_started_ = false;
    video_drain_started_ = false;
    audio_drain_finished_ = false;
    video_drain_finished_ = false;
}

bool FfmpegDecoder::OpenAudioDecoder(const Demuxer& demuxer, std::string* error)
{
#if !PLAYER_SIRIUS_HAS_FFMPEG
    (void)demuxer;
    (void)error;
    return false;
#else
    const auto* ffmpeg_demuxer = dynamic_cast<const FfmpegDemuxer*>(&demuxer);
    if (ffmpeg_demuxer == nullptr || ffmpeg_demuxer->AudioStream() == nullptr) {
        return true;
    }
    audio_codec_context_ = OpenCodecContext(ffmpeg_demuxer->AudioStream(), error);
    return audio_codec_context_ != nullptr;
#endif
}

bool FfmpegDecoder::OpenVideoDecoder(const Demuxer& demuxer, std::string* error)
{
#if !PLAYER_SIRIUS_HAS_FFMPEG
    (void)demuxer;
    (void)error;
    return false;
#else
    const auto* ffmpeg_demuxer = dynamic_cast<const FfmpegDemuxer*>(&demuxer);
    if (ffmpeg_demuxer == nullptr || ffmpeg_demuxer->VideoStream() == nullptr) {
        return true;
    }
    video_codec_context_ = OpenCodecContext(ffmpeg_demuxer->VideoStream(), error);
    return video_codec_context_ != nullptr;
#endif
}

bool FfmpegDecoder::ReceiveFrame(AVCodecContext* context, bool audio, bool video, MediaFrame* frame, std::string* error)
{
#if !PLAYER_SIRIUS_HAS_FFMPEG
    (void)context;
    (void)audio;
    (void)video;
    (void)frame;
    (void)error;
    return false;
#else
    AVFrame* native_frame = av_frame_alloc();
    if (native_frame == nullptr) {
        if (error != nullptr) {
            *error = "av_frame_alloc failed";
        }
        return false;
    }

    const int rc = avcodec_receive_frame(context, native_frame);
    if (rc == AVERROR(EAGAIN) || rc == AVERROR_EOF) {
        av_frame_free(&native_frame);
        *frame = MediaFrame();
        return true;
    }
    if (rc < 0) {
        av_frame_free(&native_frame);
        if (error != nullptr) {
            *error = MakeErrorString("avcodec_receive_frame failed", rc);
        }
        return false;
    }

    *frame = MediaFrame();
    frame->audio = audio;
    frame->video = video;
    frame->key_frame = native_frame->key_frame != 0;
    frame->pts_ms = ToMilliseconds(native_frame->best_effort_timestamp, context->time_base);
    frame->duration_ms = ToMilliseconds(native_frame->duration, context->time_base);
    frame->stream_index = native_frame->pkt_pos >= 0 ? 0 : -1;
    if (video) {
        frame->width = native_frame->width;
        frame->height = native_frame->height;
    }
    if (audio) {
        frame->sample_rate = native_frame->sample_rate;
        frame->channels = native_frame->ch_layout.nb_channels;
        frame->samples_per_channel = native_frame->nb_samples;
    }
    frame->native_frame = std::shared_ptr<void>(
        native_frame,
        [](void* value) {
            AVFrame* frame_to_free = static_cast<AVFrame*>(value);
            av_frame_free(&frame_to_free);
        });
    return true;
#endif
}

bool FfmpegDecoder::DrainContext(
    AVCodecContext* context,
    bool* drain_started,
    bool* drain_finished,
    bool audio,
    bool video,
    MediaFrame* frame,
    std::string* error)
{
#if !PLAYER_SIRIUS_HAS_FFMPEG
    (void)context;
    (void)drain_started;
    (void)drain_finished;
    (void)audio;
    (void)video;
    (void)frame;
    (void)error;
    return false;
#else
    if (context == nullptr || drain_started == nullptr || drain_finished == nullptr || frame == nullptr) {
        if (error != nullptr) {
            *error = "decoder drain context is invalid";
        }
        return false;
    }
    if (*drain_finished) {
        *frame = MediaFrame();
        return true;
    }
    if (!*drain_started) {
        const int rc = avcodec_send_packet(context, nullptr);
        if (rc < 0 && rc != AVERROR_EOF) {
            if (error != nullptr) {
                *error = MakeErrorString("avcodec_send_packet(null) failed", rc);
            }
            return false;
        }
        *drain_started = true;
    }
    const bool ok = ReceiveFrame(context, audio, video, frame, error);
    if (!ok) {
        return false;
    }
    if (!frame->audio && !frame->video) {
        *drain_finished = true;
    }
    return true;
#endif
}

} // namespace player_sirius
