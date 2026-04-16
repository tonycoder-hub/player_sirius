#include "player_core.h"

#include <algorithm>
#include <chrono>
#include <utility>

namespace player_sirius {

NativePlayerCore::NativePlayerCore()
    : backend_(CreateSoftDecodeBackend())
{
    const Capability capability = backend_->GetCapability();
    snapshot_.backend_name = capability.backend_name;
    snapshot_.stage = capability.stage;
    snapshot_.metrics = backend_->GetMetrics();
}

NativePlayerCore::~NativePlayerCore()
{
    // Ensure no background thread keeps running past addon teardown.
    StopRuntimeMonitor();
    if (backend_) {
        backend_->Release();
    }
}

Capability NativePlayerCore::GetCapability() const
{
    return backend_->GetCapability();
}

StateSnapshot NativePlayerCore::GetState() const
{
    const_cast<NativePlayerCore*>(this)->SyncSnapshotRuntime();
    return snapshot_;
}

void NativePlayerCore::SetEventSink(EventSink sink)
{
    event_sink_ = std::move(sink);
}

int NativePlayerCore::Prepare(const SourceSpec& source)
{
    {
        std::lock_guard<std::mutex> lock(snapshot_mutex_);
        snapshot_.source = source.source;
        snapshot_.surface_id = source.surface_id;
        snapshot_.position_ms = 0;
        snapshot_.last_error.clear();
        snapshot_.error_stage.clear();
    }
    SyncSnapshotRuntime();

    std::string error;
    if (!backend_->Prepare(source, &error)) {
        Fail(error);
        return -1;
    }

    {
        std::lock_guard<std::mutex> lock(snapshot_mutex_);
        snapshot_.state = PlaybackState::kPrepared;
    }
    SyncSnapshotRuntime();
    Emit("prepared");
    Emit("metrics", "runtime metrics updated");
    return 0;
}

void NativePlayerCore::Play()
{
    std::string error;
    if (!backend_->Play(&error)) {
        Fail(error);
        return;
    }
    {
        std::lock_guard<std::mutex> lock(snapshot_mutex_);
        snapshot_.state = PlaybackState::kPlaying;
        snapshot_.last_error.clear();
        snapshot_.error_stage.clear();
    }
    SyncSnapshotRuntime();
    StartRuntimeMonitor();
    Emit("playing");
    Emit("metrics", "runtime metrics updated");
}

void NativePlayerCore::Pause()
{
    std::string error;
    if (!backend_->Pause(&error)) {
        Fail(error);
        return;
    }
    {
        std::lock_guard<std::mutex> lock(snapshot_mutex_);
        snapshot_.state = PlaybackState::kPaused;
        snapshot_.last_error.clear();
        snapshot_.error_stage.clear();
    }
    SyncSnapshotRuntime();
    StopRuntimeMonitor();
    Emit("paused");
    Emit("metrics", "runtime metrics updated");
}

void NativePlayerCore::Stop()
{
    std::string error;
    if (!backend_->Stop(&error)) {
        Fail(error);
        return;
    }
    {
        std::lock_guard<std::mutex> lock(snapshot_mutex_);
        snapshot_.state = PlaybackState::kStopped;
        snapshot_.position_ms = 0;
        snapshot_.last_error.clear();
        snapshot_.error_stage.clear();
    }
    SyncSnapshotRuntime();
    StopRuntimeMonitor();
    Emit("stopped");
    Emit("metrics", "runtime metrics updated");
}

void NativePlayerCore::Seek(int64_t position_ms)
{
    const int64_t normalized = std::max<int64_t>(0, position_ms);
    std::string error;
    if (!backend_->Seek(normalized, &error)) {
        Fail(error);
        return;
    }
    {
        std::lock_guard<std::mutex> lock(snapshot_mutex_);
        snapshot_.position_ms = normalized;
        snapshot_.last_error.clear();
        snapshot_.error_stage.clear();
    }
    SyncSnapshotRuntime();
    Emit("seek", "position updated");
    Emit("metrics", "runtime metrics updated");
}

void NativePlayerCore::Release()
{
    backend_->Release();
    StopRuntimeMonitor();
    {
        std::lock_guard<std::mutex> lock(snapshot_mutex_);
        snapshot_ = StateSnapshot();
        const Capability capability = backend_->GetCapability();
        snapshot_.backend_name = capability.backend_name;
        snapshot_.stage = capability.stage;
        snapshot_.metrics = backend_->GetMetrics();
    }
    Emit("released");
}

void NativePlayerCore::Emit(const std::string& type, const std::string& message) const
{
    if (!event_sink_) {
        return;
    }
    std::lock_guard<std::mutex> lock(snapshot_mutex_);
    Event event;
    event.type = type;
    event.message = message;
    event.snapshot = snapshot_;
    event_sink_(event);
}

void NativePlayerCore::Fail(const std::string& message)
{
    StopRuntimeMonitor();
    {
        std::lock_guard<std::mutex> lock(snapshot_mutex_);
        snapshot_.state = PlaybackState::kError;
        snapshot_.last_error = message;
    }
    SyncSnapshotRuntime();
    {
        std::lock_guard<std::mutex> lock(snapshot_mutex_);
        snapshot_.error_stage = snapshot_.stage;
    }
    Emit("error", message);
    Emit("metrics", "runtime metrics updated");
}

void NativePlayerCore::SyncSnapshotRuntime()
{
    std::lock_guard<std::mutex> lock(snapshot_mutex_);
    snapshot_.stage = backend_->GetStage();
    snapshot_.metrics = backend_->GetMetrics();
    if (snapshot_.metrics.audio_clock_ms > 0) {
        snapshot_.position_ms = snapshot_.metrics.audio_clock_ms;
    } else if (snapshot_.metrics.video_clock_ms > 0) {
        snapshot_.position_ms = snapshot_.metrics.video_clock_ms;
    }
    if (snapshot_.state == PlaybackState::kPlaying && snapshot_.stage == "drained") {
        snapshot_.state = PlaybackState::kCompleted;
    }
}

void NativePlayerCore::StartRuntimeMonitor()
{
    if (runtime_monitor_running_.load()) {
        return;
    }
    // If the previous monitor loop exited naturally, its std::thread is still joinable.
    // Re-assigning a joinable std::thread triggers std::terminate.
    if (runtime_monitor_thread_.joinable()) {
        runtime_monitor_thread_.join();
    }
    runtime_monitor_stop_requested_.store(false);
    runtime_monitor_running_.store(true);
    runtime_monitor_thread_ = std::thread(&NativePlayerCore::RuntimeMonitorLoop, this);
}

void NativePlayerCore::StopRuntimeMonitor()
{
    runtime_monitor_stop_requested_.store(true);
    if (runtime_monitor_thread_.joinable()) {
        runtime_monitor_thread_.join();
    }
    runtime_monitor_running_.store(false);
}

void NativePlayerCore::RuntimeMonitorLoop()
{
    int64_t last_emitted_audio_clock_ms = -1;
    std::string last_stage;
    while (!runtime_monitor_stop_requested_.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(120));
        SyncSnapshotRuntime();
        StateSnapshot current_snapshot;
        {
            std::lock_guard<std::mutex> lock(snapshot_mutex_);
            current_snapshot = snapshot_;
        }
        if (current_snapshot.metrics.audio_clock_ms != last_emitted_audio_clock_ms || current_snapshot.stage != last_stage) {
          last_emitted_audio_clock_ms = current_snapshot.metrics.audio_clock_ms;
          last_stage = current_snapshot.stage;
          Emit("metrics", "runtime monitor updated");
        }
        if (current_snapshot.state == PlaybackState::kCompleted) {
            Emit("completed", "playback completed");
            runtime_monitor_stop_requested_.store(true);
            break;
        }
    }
    runtime_monitor_running_.store(false);
}

} // namespace player_sirius
