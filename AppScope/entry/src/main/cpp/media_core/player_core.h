#pragma once

#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

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
    void StartRuntimeMonitor();
    void StopRuntimeMonitor();
    void RuntimeMonitorLoop();

    std::unique_ptr<SoftDecodeBackend> backend_;
    mutable StateSnapshot snapshot_;
    mutable std::mutex snapshot_mutex_;
    EventSink event_sink_;
    std::thread runtime_monitor_thread_;
    std::atomic<bool> runtime_monitor_running_{false};
    std::atomic<bool> runtime_monitor_stop_requested_{false};
};

} // namespace player_sirius
