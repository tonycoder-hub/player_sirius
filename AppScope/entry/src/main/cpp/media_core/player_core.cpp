#include "player_core.h"

#include <algorithm>
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

NativePlayerCore::~NativePlayerCore() = default;

Capability NativePlayerCore::GetCapability() const
{
    return backend_->GetCapability();
}

StateSnapshot NativePlayerCore::GetState() const
{
    return snapshot_;
}

void NativePlayerCore::SetEventSink(EventSink sink)
{
    event_sink_ = std::move(sink);
}

int NativePlayerCore::Prepare(const SourceSpec& source)
{
    snapshot_.source = source.source;
    snapshot_.surface_id = source.surface_id;
    snapshot_.position_ms = 0;
    snapshot_.last_error.clear();
    snapshot_.error_stage.clear();
    SyncSnapshotRuntime();

    std::string error;
    if (!backend_->Prepare(source, &error)) {
        Fail(error);
        return -1;
    }

    snapshot_.state = PlaybackState::kPrepared;
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
    snapshot_.state = PlaybackState::kPlaying;
    snapshot_.last_error.clear();
    snapshot_.error_stage.clear();
    SyncSnapshotRuntime();
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
    snapshot_.state = PlaybackState::kPaused;
    snapshot_.last_error.clear();
    snapshot_.error_stage.clear();
    SyncSnapshotRuntime();
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
    snapshot_.state = PlaybackState::kStopped;
    snapshot_.position_ms = 0;
    snapshot_.last_error.clear();
    snapshot_.error_stage.clear();
    SyncSnapshotRuntime();
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
    snapshot_.position_ms = normalized;
    snapshot_.last_error.clear();
    snapshot_.error_stage.clear();
    SyncSnapshotRuntime();
    Emit("seek", "position updated");
    Emit("metrics", "runtime metrics updated");
}

void NativePlayerCore::Release()
{
    backend_->Release();
    snapshot_ = StateSnapshot();
    const Capability capability = backend_->GetCapability();
    snapshot_.backend_name = capability.backend_name;
    snapshot_.stage = capability.stage;
    snapshot_.metrics = backend_->GetMetrics();
    Emit("released");
}

void NativePlayerCore::Emit(const std::string& type, const std::string& message) const
{
    if (!event_sink_) {
        return;
    }
    Event event;
    event.type = type;
    event.message = message;
    event.snapshot = snapshot_;
    event_sink_(event);
}

void NativePlayerCore::Fail(const std::string& message)
{
    snapshot_.state = PlaybackState::kError;
    snapshot_.last_error = message;
    SyncSnapshotRuntime();
    snapshot_.error_stage = snapshot_.stage;
    Emit("error", message);
    Emit("metrics", "runtime metrics updated");
}

void NativePlayerCore::SyncSnapshotRuntime()
{
    snapshot_.stage = backend_->GetStage();
    snapshot_.metrics = backend_->GetMetrics();
}

} // namespace player_sirius
