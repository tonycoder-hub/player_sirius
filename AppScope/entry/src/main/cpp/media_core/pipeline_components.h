#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "player_types.h"

namespace player_sirius {

struct MediaStreamInfo {
    bool valid = false;
    bool audio = false;
    bool video = false;
    int stream_index = -1;
    std::string codec_name;
    int64_t duration_ms = 0;
    int64_t bit_rate = 0;
    int width = 0;
    int height = 0;
    int sample_rate = 0;
    int channels = 0;
};

struct MediaPacket {
    bool end_of_stream = false;
    bool audio = false;
    bool video = false;
    bool key_frame = false;
    int stream_index = -1;
    int64_t pts_ms = 0;
    int64_t dts_ms = 0;
    int64_t duration_ms = 0;
    std::string codec_hint;
    std::shared_ptr<void> native_packet;
};

struct MediaFrame {
    bool audio = false;
    bool video = false;
    bool key_frame = false;
    int stream_index = -1;
    int64_t pts_ms = 0;
    int64_t duration_ms = 0;
    int width = 0;
    int height = 0;
    int sample_rate = 0;
    int channels = 0;
    int samples_per_channel = 0;
    std::shared_ptr<void> native_frame;
};

class Demuxer {
public:
    virtual ~Demuxer() = default;

    virtual const char* Name() const = 0;
    virtual bool Open(const SourceSpec& source, std::string* error) = 0;
    virtual bool ReadPacket(MediaPacket* packet, std::string* error) = 0;
    virtual bool Seek(int64_t position_ms, std::string* error) = 0;
    virtual const MediaStreamInfo* GetPrimaryAudioStream() const = 0;
    virtual const MediaStreamInfo* GetPrimaryVideoStream() const = 0;
    virtual void Close() = 0;
};

class Decoder {
public:
    virtual ~Decoder() = default;

    virtual const char* Name() const = 0;
    virtual bool Configure(const Demuxer& demuxer, std::string* error) = 0;
    virtual bool Decode(const MediaPacket& packet, MediaFrame* frame, std::string* error) = 0;
    virtual bool Drain(MediaFrame* frame, std::string* error) = 0;
    virtual void Flush() = 0;
    virtual void Close() = 0;
};

class Renderer {
public:
    virtual ~Renderer() = default;

    virtual const char* Name() const = 0;
    virtual bool Configure(const SourceSpec& source, std::string* error) = 0;
    virtual bool Render(const MediaFrame& frame, std::string* error) = 0;
    virtual void Reset() = 0;
    virtual void Close() = 0;
};

class Clock {
public:
    virtual ~Clock() = default;

    virtual const char* Name() const = 0;
    virtual void Reset() = 0;
    virtual void Start() = 0;
    virtual void Pause() = 0;
    virtual void Seek(int64_t position_ms) = 0;
    virtual int64_t PositionMs() const = 0;
};

std::unique_ptr<Demuxer> CreateDefaultDemuxer();
std::unique_ptr<Decoder> CreateDefaultDecoder();
std::unique_ptr<Renderer> CreateDefaultRenderer();
std::unique_ptr<Clock> CreateDefaultClock();

} // namespace player_sirius
