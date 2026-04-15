#include <node_api.h>

#include <cstdint>
#include <string>
#include <vector>

#include "media_core/player_core.h"

namespace {

player_sirius::NativePlayerCore g_player_core;
napi_env g_listener_env = nullptr;
napi_ref g_listener_ref = nullptr;

napi_value MakeString(napi_env env, const std::string& value)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

napi_value MakeBoolean(napi_env env, bool value)
{
    napi_value result = nullptr;
    napi_get_boolean(env, value, &result);
    return result;
}

napi_value MakeInt64(napi_env env, int64_t value)
{
    napi_value result = nullptr;
    napi_create_int64(env, value, &result);
    return result;
}

bool ReadOptionalStringArg(napi_env env, napi_value value, std::string* output)
{
    if (output == nullptr || value == nullptr) {
        return false;
    }
    napi_valuetype value_type = napi_undefined;
    if (napi_typeof(env, value, &value_type) != napi_ok || value_type == napi_undefined || value_type == napi_null) {
        output->clear();
        return true;
    }
    if (value_type != napi_string) {
        return false;
    }
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return false;
    }
    std::vector<char> buffer(length + 1, '\0');
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &length) != napi_ok) {
        return false;
    }
    output->assign(buffer.data(), length);
    return true;
}

bool ReadInt64Arg(napi_env env, napi_value value, int64_t* output)
{
    if (output == nullptr || value == nullptr) {
        return false;
    }
    napi_valuetype value_type = napi_undefined;
    if (napi_typeof(env, value, &value_type) != napi_ok || value_type != napi_number) {
        return false;
    }
    return napi_get_value_int64(env, value, output) == napi_ok;
}

void ClearEventListener(napi_env env)
{
    if (g_listener_ref != nullptr && env != nullptr) {
        napi_delete_reference(env, g_listener_ref);
    }
    g_listener_ref = nullptr;
    g_listener_env = nullptr;
}

void DispatchEventToJs(const player_sirius::Event& event)
{
    if (g_listener_env == nullptr || g_listener_ref == nullptr) {
        return;
    }

    napi_handle_scope scope = nullptr;
    if (napi_open_handle_scope(g_listener_env, &scope) != napi_ok) {
        return;
    }

    napi_value callback = nullptr;
    napi_value global = nullptr;
    napi_value js_event = nullptr;
    napi_value ignored = nullptr;

    if (napi_get_reference_value(g_listener_env, g_listener_ref, &callback) != napi_ok ||
        napi_get_global(g_listener_env, &global) != napi_ok ||
        napi_create_object(g_listener_env, &js_event) != napi_ok) {
        napi_close_handle_scope(g_listener_env, scope);
        return;
    }

    napi_set_named_property(g_listener_env, js_event, "type", MakeString(g_listener_env, event.type));
    napi_set_named_property(g_listener_env, js_event, "message", MakeString(g_listener_env, event.message));
    napi_set_named_property(g_listener_env, js_event, "state",
        MakeString(g_listener_env, player_sirius::ToString(event.snapshot.state)));
    napi_set_named_property(g_listener_env, js_event, "source", MakeString(g_listener_env, event.snapshot.source));
    napi_set_named_property(g_listener_env, js_event, "surfaceId", MakeString(g_listener_env, event.snapshot.surface_id));
    napi_set_named_property(g_listener_env, js_event, "positionMs", MakeInt64(g_listener_env, event.snapshot.position_ms));
    napi_set_named_property(g_listener_env, js_event, "lastError", MakeString(g_listener_env, event.snapshot.last_error));
    napi_set_named_property(g_listener_env, js_event, "backendName", MakeString(g_listener_env, event.snapshot.backend_name));
    napi_set_named_property(g_listener_env, js_event, "stage", MakeString(g_listener_env, event.snapshot.stage));
    napi_set_named_property(g_listener_env, js_event, "errorStage", MakeString(g_listener_env, event.snapshot.error_stage));
    napi_set_named_property(g_listener_env, js_event, "metrics", CreateMetricsObject(g_listener_env, event.snapshot.metrics));

    napi_call_function(g_listener_env, global, callback, 1, &js_event, &ignored);
    napi_close_handle_scope(g_listener_env, scope);
}

napi_value CreateCapabilityObject(napi_env env, const player_sirius::Capability& capability)
{
    napi_value obj = nullptr;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "available", MakeBoolean(env, capability.available));
    napi_set_named_property(env, obj, "version", MakeString(env, capability.version));
    napi_set_named_property(env, obj, "backendName", MakeString(env, capability.backend_name));
    napi_set_named_property(env, obj, "blocker", MakeString(env, capability.blocker));
    napi_set_named_property(env, obj, "stage", MakeString(env, capability.stage));

    napi_value features = nullptr;
    napi_create_array_with_length(env, capability.features.size(), &features);
    for (size_t i = 0; i < capability.features.size(); ++i) {
        napi_set_element(env, features, i, MakeString(env, capability.features[i]));
    }
    napi_set_named_property(env, obj, "features", features);
    return obj;
}

napi_value CreateMetricsObject(napi_env env, const player_sirius::PlaybackMetrics& metrics)
{
    napi_value obj = nullptr;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "bufferedDurationMs", MakeInt64(env, metrics.buffered_duration_ms));
    napi_set_named_property(env, obj, "decodedAudioFrames", MakeInt64(env, metrics.decoded_audio_frames));
    napi_set_named_property(env, obj, "decodedVideoFrames", MakeInt64(env, metrics.decoded_video_frames));
    napi_set_named_property(env, obj, "renderedAudioFrames", MakeInt64(env, metrics.rendered_audio_frames));
    napi_set_named_property(env, obj, "renderedVideoFrames", MakeInt64(env, metrics.rendered_video_frames));
    napi_set_named_property(env, obj, "droppedVideoFrames", MakeInt64(env, metrics.dropped_video_frames));
    napi_set_named_property(env, obj, "emittedEvents", MakeInt64(env, metrics.emitted_events));
    return obj;
}

napi_value CreateStateObject(napi_env env, const player_sirius::StateSnapshot& snapshot)
{
    napi_value obj = nullptr;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "state", MakeString(env, player_sirius::ToString(snapshot.state)));
    napi_set_named_property(env, obj, "source", MakeString(env, snapshot.source));
    napi_set_named_property(env, obj, "surfaceId", MakeString(env, snapshot.surface_id));
    napi_set_named_property(env, obj, "positionMs", MakeInt64(env, snapshot.position_ms));
    napi_set_named_property(env, obj, "lastError", MakeString(env, snapshot.last_error));
    napi_set_named_property(env, obj, "stage", MakeString(env, snapshot.stage));
    napi_set_named_property(env, obj, "errorStage", MakeString(env, snapshot.error_stage));
    napi_set_named_property(env, obj, "metrics", CreateMetricsObject(env, snapshot.metrics));
    return obj;
}

napi_value GetCapability(napi_env env, napi_callback_info info)
{
    return CreateCapabilityObject(env, g_player_core.GetCapability());
}

napi_value GetState(napi_env env, napi_callback_info info)
{
    return CreateStateObject(env, g_player_core.GetState());
}

napi_value SetEventListener(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    ClearEventListener(env);
    if (argc > 0 && argv[0] != nullptr) {
        napi_valuetype value_type = napi_undefined;
        if (napi_typeof(env, argv[0], &value_type) == napi_ok && value_type == napi_function) {
            napi_create_reference(env, argv[0], 1, &g_listener_ref);
            g_listener_env = env;
            g_player_core.SetEventSink(DispatchEventToJs);
        } else {
            g_player_core.SetEventSink(nullptr);
        }
    } else {
        g_player_core.SetEventSink(nullptr);
    }

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value ClearListener(napi_env env, napi_callback_info info)
{
    ClearEventListener(env);
    g_player_core.SetEventSink(nullptr);
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value Prepare(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    std::string source;
    std::string surface_id;
    napi_value result = nullptr;
    napi_create_int32(env, -1, &result);
    if (argc < 1 || !ReadOptionalStringArg(env, argv[0], &source) || source.empty()) {
        return result;
    }
    if (argc >= 2 && !ReadOptionalStringArg(env, argv[1], &surface_id)) {
        return result;
    }

    const int prepare_result = g_player_core.Prepare({source, surface_id});
    napi_create_int32(env, prepare_result, &result);
    return result;
}

napi_value Play(napi_env env, napi_callback_info info)
{
    g_player_core.Play();
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value Pause(napi_env env, napi_callback_info info)
{
    g_player_core.Pause();
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value Stop(napi_env env, napi_callback_info info)
{
    g_player_core.Stop();
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value Seek(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    int64_t position_ms = 0;
    if (argc >= 1 && ReadInt64Arg(env, argv[0], &position_ms)) {
        g_player_core.Seek(position_ms);
    }

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value Release(napi_env env, napi_callback_info info)
{
    g_player_core.Release();
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"getCapability", nullptr, GetCapability, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getState", nullptr, GetState, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setEventListener", nullptr, SetEventListener, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"clearEventListener", nullptr, ClearListener, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"prepare", nullptr, Prepare, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"play", nullptr, Play, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pause", nullptr, Pause, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"seek", nullptr, Seek, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"release", nullptr, Release, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

} // namespace

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
