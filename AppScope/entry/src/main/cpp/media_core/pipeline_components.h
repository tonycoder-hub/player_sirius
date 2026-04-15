#pragma once

#include <cstdint>
#include <memory>
#include <string>

#include "player_types.h"

namespace player_sirius {

struct MediaPacket {
    bool end_of_stream = false;
    int64_t pts_ms = 0;
    std::string codec_hint;
};

struct MediaFrame {
    bool audio = false;
    bool video = false;
    int64_t pts_ms = 0;
};

class Demuxer {
public:
    virtual ~Demuxer() = default;

    virtual const char* Name() const = 0;
    virtual bool Open(const SourceSpec& source, std::string* error) = 0;
    virtual bool ReadPacket(MediaPacket* packet, std::string* error) = 0;
    virtual bool Seek(int64_t position_ms, std::string* error) = 0;
    virtual void Close() = 0;
};

class Decoder {
public:
    virtual ~Decoder() = default;

    virtual const char* Name() const = 0;
    virtual bool Configure(const Demuxer& demuxer, std::string* error) = 0;
    virtual bool Decode(const MediaPacket& packet, MediaFrame* frame, std::string* error) = 0;
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
