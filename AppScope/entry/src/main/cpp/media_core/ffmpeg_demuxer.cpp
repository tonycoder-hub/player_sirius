#include "ffmpeg_demuxer.h"

#include <memory>
#include <utility>

#if PLAYER_SIRIUS_HAS_FFMPEG
extern "C" {
#include <libavcodec/packet.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/error.h>
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

std::string CodecName(const AVCodecParameters* codec_parameters)
{
    if (codec_parameters == nullptr) {
        return "";
    }
    const AVCodecDescriptor* descriptor = avcodec_descriptor_get(codec_parameters->codec_id);
    return descriptor != nullptr && descriptor->name != nullptr ? std::string(descriptor->name) : "";
}

MediaStreamInfo BuildStreamInfo(const AVStream* stream, bool audio, bool video)
{
    MediaStreamInfo info;
    if (stream == nullptr || stream->codecpar == nullptr) {
        return info;
    }
    info.valid = true;
    info.audio = audio;
    info.video = video;
    info.stream_index = stream->index;
    info.codec_name = CodecName(stream->codecpar);
    info.duration_ms = ToMilliseconds(stream->duration, stream->time_base);
    info.bit_rate = stream->codecpar->bit_rate;
    if (video) {
        info.width = stream->codecpar->width;
        info.height = stream->codecpar->height;
    }
    if (audio) {
        info.sample_rate = stream->codecpar->sample_rate;
        info.channels = stream->codecpar->ch_layout.nb_channels;
    }
    return info;
}
#endif

} // namespace

FfmpegDemuxer::FfmpegDemuxer() = default;

FfmpegDemuxer::~FfmpegDemuxer()
{
    Close();
}

const char* FfmpegDemuxer::Name() const
{
    return "ffmpeg-demuxer";
}

bool FfmpegDemuxer::Open(const SourceSpec& source, std::string* error)
{
#if !PLAYER_SIRIUS_HAS_FFMPEG
    if (error != nullptr) {
        *error = "FFmpeg demuxer backend is not linked";
    }
    return false;
#else
    Close();
    if (source.source.empty()) {
        if (error != nullptr) {
            *error = "demuxer source is empty";
        }
        return false;
    }

    source_ = source;
    AVFormatContext* context = nullptr;
    int rc = avformat_open_input(&context, source.source.c_str(), nullptr, nullptr);
    if (rc < 0) {
        if (error != nullptr) {
            *error = MakeErrorString("avformat_open_input failed", rc);
        }
        return false;
    }

    rc = avformat_find_stream_info(context, nullptr);
    if (rc < 0) {
        if (error != nullptr) {
            *error = MakeErrorString("avformat_find_stream_info failed", rc);
        }
        avformat_close_input(&context);
        return false;
    }

    format_context_ = context;
    if (!PopulateStreamInfos(error)) {
        Close();
        return false;
    }
    return true;
#endif
}

bool FfmpegDemuxer::ReadPacket(MediaPacket* packet, std::string* error)
{
    if (packet == nullptr) {
        if (error != nullptr) {
            *error = "demuxer packet output is null";
        }
        return false;
    }
#if !PLAYER_SIRIUS_HAS_FFMPEG
    if (error != nullptr) {
        *error = "FFmpeg demuxer backend is not linked";
    }
    return false;
#else
    if (format_context_ == nullptr) {
        if (error != nullptr) {
            *error = "demuxer is not opened";
        }
        return false;
    }

    AVPacket* native_packet = av_packet_alloc();
    if (native_packet == nullptr) {
        if (error != nullptr) {
            *error = "av_packet_alloc failed";
        }
        return false;
    }

    const int rc = av_read_frame(format_context_, native_packet);
    if (rc == AVERROR_EOF) {
        av_packet_free(&native_packet);
        *packet = MediaPacket();
        packet->end_of_stream = true;
        return true;
    }
    if (rc < 0) {
        av_packet_free(&native_packet);
        if (error != nullptr) {
            *error = MakeErrorString("av_read_frame failed", rc);
        }
        return false;
    }

    const AVStream* stream = format_context_->streams[native_packet->stream_index];
    *packet = MediaPacket();
    packet->stream_index = native_packet->stream_index;
    packet->audio = native_packet->stream_index == audio_stream_index_;
    packet->video = native_packet->stream_index == video_stream_index_;
    packet->key_frame = (native_packet->flags & AV_PKT_FLAG_KEY) != 0;
    packet->pts_ms = ToMilliseconds(native_packet->pts, stream->time_base);
    packet->dts_ms = ToMilliseconds(native_packet->dts, stream->time_base);
    packet->duration_ms = ToMilliseconds(native_packet->duration, stream->time_base);
    packet->codec_hint = packet->audio ? audio_stream_info_.codec_name : video_stream_info_.codec_name;
    packet->native_packet = std::shared_ptr<void>(
        native_packet,
        [](void* value) {
            AVPacket* packet_to_free = static_cast<AVPacket*>(value);
            av_packet_free(&packet_to_free);
        });
    return true;
#endif
}

bool FfmpegDemuxer::Seek(int64_t position_ms, std::string* error)
{
#if !PLAYER_SIRIUS_HAS_FFMPEG
    if (error != nullptr) {
        *error = "FFmpeg demuxer backend is not linked";
    }
    return false;
#else
    if (format_context_ == nullptr) {
        if (error != nullptr) {
            *error = "demuxer is not opened";
        }
        return false;
    }
    const int64_t target = av_rescale_q(position_ms, AVRational{1, 1000}, AV_TIME_BASE_Q);
    const int rc = av_seek_frame(format_context_, -1, target, AVSEEK_FLAG_BACKWARD);
    if (rc < 0) {
        if (error != nullptr) {
            *error = MakeErrorString("av_seek_frame failed", rc);
        }
        return false;
    }
    avformat_flush(format_context_);
    return true;
#endif
}

const MediaStreamInfo* FfmpegDemuxer::GetPrimaryAudioStream() const
{
    return audio_stream_info_.valid ? &audio_stream_info_ : nullptr;
}

const MediaStreamInfo* FfmpegDemuxer::GetPrimaryVideoStream() const
{
    return video_stream_info_.valid ? &video_stream_info_ : nullptr;
}

void FfmpegDemuxer::Close()
{
#if PLAYER_SIRIUS_HAS_FFMPEG
    if (format_context_ != nullptr) {
        avformat_close_input(&format_context_);
    }
#endif
    format_context_ = nullptr;
    audio_stream_index_ = -1;
    video_stream_index_ = -1;
    audio_stream_info_ = MediaStreamInfo();
    video_stream_info_ = MediaStreamInfo();
    source_ = SourceSpec();
}

AVFormatContext* FfmpegDemuxer::FormatContext() const
{
    return format_context_;
}

AVStream* FfmpegDemuxer::AudioStream() const
{
#if PLAYER_SIRIUS_HAS_FFMPEG
    if (format_context_ == nullptr || audio_stream_index_ < 0) {
        return nullptr;
    }
    return format_context_->streams[audio_stream_index_];
#else
    return nullptr;
#endif
}

AVStream* FfmpegDemuxer::VideoStream() const
{
#if PLAYER_SIRIUS_HAS_FFMPEG
    if (format_context_ == nullptr || video_stream_index_ < 0) {
        return nullptr;
    }
    return format_context_->streams[video_stream_index_];
#else
    return nullptr;
#endif
}

bool FfmpegDemuxer::PopulateStreamInfos(std::string* error)
{
#if !PLAYER_SIRIUS_HAS_FFMPEG
    if (error != nullptr) {
        *error = "FFmpeg demuxer backend is not linked";
    }
    return false;
#else
    audio_stream_index_ = av_find_best_stream(format_context_, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
    video_stream_index_ = av_find_best_stream(format_context_, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);

    if (audio_stream_index_ < 0 && video_stream_index_ < 0) {
        if (error != nullptr) {
            *error = "no playable audio/video streams found";
        }
        return false;
    }

    if (audio_stream_index_ >= 0) {
        audio_stream_info_ = BuildStreamInfo(format_context_->streams[audio_stream_index_], true, false);
    }
    if (video_stream_index_ >= 0) {
        video_stream_info_ = BuildStreamInfo(format_context_->streams[video_stream_index_], false, true);
    }
    return true;
#endif
}

} // namespace player_sirius
