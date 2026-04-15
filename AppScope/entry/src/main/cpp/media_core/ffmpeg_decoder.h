#pragma once

#include <string>

#include "pipeline_components.h"

struct AVCodecContext;

namespace player_sirius {

class FfmpegDecoder final : public Decoder {
public:
    FfmpegDecoder();
    ~FfmpegDecoder() override;

    const char* Name() const override;
    bool Configure(const Demuxer& demuxer, std::string* error) override;
    bool Decode(const MediaPacket& packet, MediaFrame* frame, std::string* error) override;
    bool Drain(MediaFrame* frame, std::string* error) override;
    void Flush() override;
    void Close() override;

private:
    bool OpenAudioDecoder(const Demuxer& demuxer, std::string* error);
    bool OpenVideoDecoder(const Demuxer& demuxer, std::string* error);
    bool ReceiveFrame(AVCodecContext* context, bool audio, bool video, MediaFrame* frame, std::string* error);
    bool DrainContext(AVCodecContext* context, bool* drain_started, bool* drain_finished, bool audio, bool video, MediaFrame* frame, std::string* error);

    AVCodecContext* audio_codec_context_ = nullptr;
    AVCodecContext* video_codec_context_ = nullptr;
    bool audio_drain_started_ = false;
    bool video_drain_started_ = false;
    bool audio_drain_finished_ = false;
    bool video_drain_finished_ = false;
};

} // namespace player_sirius
