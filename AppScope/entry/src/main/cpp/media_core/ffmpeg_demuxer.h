#pragma once

#include <string>

#include "pipeline_components.h"

struct AVFormatContext;
struct AVStream;

namespace player_sirius {

class FfmpegDemuxer final : public Demuxer {
public:
    FfmpegDemuxer();
    ~FfmpegDemuxer() override;

    const char* Name() const override;
    bool Open(const SourceSpec& source, std::string* error) override;
    bool ReadPacket(MediaPacket* packet, std::string* error) override;
    bool Seek(int64_t position_ms, std::string* error) override;
    const MediaStreamInfo* GetPrimaryAudioStream() const override;
    const MediaStreamInfo* GetPrimaryVideoStream() const override;
    void Close() override;

    AVFormatContext* FormatContext() const;
    AVStream* AudioStream() const;
    AVStream* VideoStream() const;

private:
    bool PopulateStreamInfos(std::string* error);

    SourceSpec source_;
    AVFormatContext* format_context_ = nullptr;
    int audio_stream_index_ = -1;
    int video_stream_index_ = -1;
    MediaStreamInfo audio_stream_info_;
    MediaStreamInfo video_stream_info_;
};

} // namespace player_sirius
