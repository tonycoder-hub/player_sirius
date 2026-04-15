#include "video_converter.h"

#if PLAYER_SIRIUS_HAS_FFMPEG
extern "C" {
#include <libavutil/error.h>
#include <libavutil/frame.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}
#endif

namespace player_sirius {

struct VideoConverter::Impl {
#if PLAYER_SIRIUS_HAS_FFMPEG
    SwsContext* sws = nullptr;
#endif
    int width = 0;
    int height = 0;
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

VideoConverter::VideoConverter()
    : impl_(new Impl())
{
}

VideoConverter::~VideoConverter()
{
    Reset();
    delete impl_;
    impl_ = nullptr;
}

bool VideoConverter::Configure(const MediaFrame& frame, std::string* error)
{
    if (!frame.video || !frame.native_frame) {
        if (error != nullptr) {
            *error = "video converter requires decoded video frame";
        }
        return false;
    }
#if !PLAYER_SIRIUS_HAS_FFMPEG
    if (error != nullptr) {
        *error = "FFmpeg video converter backend is not linked";
    }
    return false;
#else
    Reset();
    AVFrame* native_frame = static_cast<AVFrame*>(frame.native_frame.get());
    impl_->width = native_frame->width;
    impl_->height = native_frame->height;
    impl_->sws = sws_getContext(
        native_frame->width,
        native_frame->height,
        static_cast<AVPixelFormat>(native_frame->format),
        native_frame->width,
        native_frame->height,
        AV_PIX_FMT_RGBA,
        SWS_BILINEAR,
        nullptr,
        nullptr,
        nullptr);
    if (impl_->sws == nullptr) {
        if (error != nullptr) {
            *error = "sws_getContext failed";
        }
        return false;
    }
    return true;
#endif
}

bool VideoConverter::Convert(const MediaFrame& frame, VideoPixelBuffer* buffer, std::string* error)
{
    if (buffer == nullptr) {
        if (error != nullptr) {
            *error = "video converter output is null";
        }
        return false;
    }
    if (!frame.video || !frame.native_frame) {
        if (error != nullptr) {
            *error = "video converter requires decoded video frame";
        }
        return false;
    }
#if !PLAYER_SIRIUS_HAS_FFMPEG
    if (error != nullptr) {
        *error = "FFmpeg video converter backend is not linked";
    }
    return false;
#else
    if (impl_->sws == nullptr && !Configure(frame, error)) {
        return false;
    }

    AVFrame* native_frame = static_cast<AVFrame*>(frame.native_frame.get());
    const int rgba_stride = native_frame->width * 4;
    std::vector<uint8_t> rgba(static_cast<size_t>(rgba_stride * native_frame->height), 0);
    uint8_t* destination_data[4] = {rgba.data(), nullptr, nullptr, nullptr};
    int destination_linesize[4] = {rgba_stride, 0, 0, 0};

    const int scaled_height = sws_scale(
        impl_->sws,
        native_frame->data,
        native_frame->linesize,
        0,
        native_frame->height,
        destination_data,
        destination_linesize);
    if (scaled_height <= 0) {
        if (error != nullptr) {
            *error = MakeErrorString("sws_scale failed", scaled_height);
        }
        return false;
    }

    buffer->width = native_frame->width;
    buffer->height = native_frame->height;
    buffer->stride = rgba_stride;
    buffer->rgba = std::move(rgba);
    return true;
#endif
}

void VideoConverter::Reset()
{
#if PLAYER_SIRIUS_HAS_FFMPEG
    if (impl_ != nullptr && impl_->sws != nullptr) {
        sws_freeContext(impl_->sws);
        impl_->sws = nullptr;
    }
#endif
    if (impl_ != nullptr) {
        impl_->width = 0;
        impl_->height = 0;
    }
}

} // namespace player_sirius
