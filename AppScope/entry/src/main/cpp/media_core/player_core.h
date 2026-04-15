#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>

#include "player_types.h"
#include "soft_backend.h"

namespace player_sirius {

class NativePlayerCore {
public:
    using EventSink = std::function<void(const Event&)>;

    NativePlayerCore();
    ~NativePlayerCore();

    Capability GetCapability() const;
    StateSnapshot GetState() const;
    void SetEventSink(EventSink sink);

    int Prepare(const SourceSpec& source);
    void Play();
    void Pause();
    void Stop();
    void Seek(int64_t position_ms);
    void Release();

private:
    void Emit(const std::string& type, const std::string& message = "") const;
    void Fail(const std::string& message);
    void SyncSnapshotRuntime();

    std::unique_ptr<SoftDecodeBackend> backend_;
    StateSnapshot snapshot_;
    EventSink event_sink_;
};

} // namespace player_sirius
