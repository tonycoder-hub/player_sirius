#include <node_api.h>

#include <cstdint>
#include <string>
#include <vector>

namespace {

#if PLAYER_SIRIUS_HAS_LIBSMB2
constexpr const char* kSmbBackendName = "libsmb2-linked";
constexpr const char* kSmbBlocker = "libsmb2 detected, but SMB directory and file operations are not implemented yet";
#else
constexpr const char* kSmbBackendName = "libsmb2-placeholder";
constexpr const char* kSmbBlocker = "libsmb2 native dependency is not linked into current repository";
#endif

struct SmbBridgeState {
    std::string session_state = "idle";
    std::string profile_name;
    std::string host;
    int32_t port = 445;
    std::string share;
    std::string username;
    std::string path = "/";
    std::string last_error;
};

SmbBridgeState g_smb_state;
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

napi_value MakeInt32(napi_env env, int32_t value)
{
    napi_value result = nullptr;
    napi_create_int32(env, value, &result);
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

bool ReadInt32Arg(napi_env env, napi_value value, int32_t* output)
{
    if (output == nullptr || value == nullptr) {
        return false;
    }
    napi_valuetype value_type = napi_undefined;
    if (napi_typeof(env, value, &value_type) != napi_ok || value_type != napi_number) {
        return false;
    }
    return napi_get_value_int32(env, value, output) == napi_ok;
}

void ClearEventListener(napi_env env)
{
    if (g_listener_ref != nullptr && env != nullptr) {
        napi_delete_reference(env, g_listener_ref);
    }
    g_listener_ref = nullptr;
    g_listener_env = nullptr;
}

napi_value CreateCapabilityObject(napi_env env)
{
    napi_value obj = nullptr;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "available", MakeBoolean(env, PLAYER_SIRIUS_HAS_LIBSMB2 == 1));
    napi_set_named_property(env, obj, "version", MakeString(env, "0.1.0-smb-bridge"));
    napi_set_named_property(env, obj, "backendName", MakeString(env, kSmbBackendName));
    napi_set_named_property(env, obj, "blocker", MakeString(env, kSmbBlocker));
    napi_value features = nullptr;
    napi_create_array_with_length(env, 5, &features);
    napi_set_element(env, features, 0, MakeString(env, "profile-validation"));
    napi_set_element(env, features, 1, MakeString(env, "session-state"));
    napi_set_element(env, features, 2, MakeString(env, "native-dependency-slot"));
    napi_set_element(env, features, 3, MakeString(env, "directory-list-boundary"));
    napi_set_element(env, features, 4, MakeString(env, "open-file-boundary"));
    napi_set_named_property(env, obj, "features", features);
    return obj;
}

napi_value CreateStateObject(napi_env env)
{
    napi_value obj = nullptr;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "sessionState", MakeString(env, g_smb_state.session_state));
    napi_set_named_property(env, obj, "profileName", MakeString(env, g_smb_state.profile_name));
    napi_set_named_property(env, obj, "host", MakeString(env, g_smb_state.host));
    napi_set_named_property(env, obj, "port", MakeInt32(env, g_smb_state.port));
    napi_set_named_property(env, obj, "share", MakeString(env, g_smb_state.share));
    napi_set_named_property(env, obj, "username", MakeString(env, g_smb_state.username));
    napi_set_named_property(env, obj, "path", MakeString(env, g_smb_state.path));
    napi_set_named_property(env, obj, "lastError", MakeString(env, g_smb_state.last_error));
    return obj;
}

void DispatchEventToJs(const std::string& type, const std::string& message)
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

    napi_set_named_property(g_listener_env, js_event, "type", MakeString(g_listener_env, type));
    napi_set_named_property(g_listener_env, js_event, "message", MakeString(g_listener_env, message));
    napi_set_named_property(g_listener_env, js_event, "sessionState", MakeString(g_listener_env, g_smb_state.session_state));
    napi_set_named_property(g_listener_env, js_event, "profileName", MakeString(g_listener_env, g_smb_state.profile_name));
    napi_set_named_property(g_listener_env, js_event, "host", MakeString(g_listener_env, g_smb_state.host));
    napi_set_named_property(g_listener_env, js_event, "port", MakeInt32(g_listener_env, g_smb_state.port));
    napi_set_named_property(g_listener_env, js_event, "share", MakeString(g_listener_env, g_smb_state.share));
    napi_set_named_property(g_listener_env, js_event, "username", MakeString(g_listener_env, g_smb_state.username));
    napi_set_named_property(g_listener_env, js_event, "path", MakeString(g_listener_env, g_smb_state.path));
    napi_set_named_property(g_listener_env, js_event, "lastError", MakeString(g_listener_env, g_smb_state.last_error));
    napi_call_function(g_listener_env, global, callback, 1, &js_event, &ignored);
    napi_close_handle_scope(g_listener_env, scope);
}

void SetError(const std::string& message)
{
    g_smb_state.session_state = "error";
    g_smb_state.last_error = message;
    DispatchEventToJs("error", message);
}

napi_value GetCapability(napi_env env, napi_callback_info info)
{
    return CreateCapabilityObject(env);
}

napi_value GetState(napi_env env, napi_callback_info info)
{
    return CreateStateObject(env);
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
        }
    }
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value ClearListener(napi_env env, napi_callback_info info)
{
    ClearEventListener(env);
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value ConfigureProfile(napi_env env, napi_callback_info info)
{
    size_t argc = 7;
    napi_value argv[7] = {nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    std::string profile_name;
    std::string host;
    int32_t port = 445;
    std::string share;
    std::string username;
    std::string password;
    std::string path = "/";

    napi_value result = nullptr;
    napi_create_int32(env, -1, &result);

    if (argc < 4 ||
        !ReadOptionalStringArg(env, argv[0], &profile_name) ||
        !ReadOptionalStringArg(env, argv[1], &host) ||
        !ReadInt32Arg(env, argv[2], &port) ||
        !ReadOptionalStringArg(env, argv[3], &share)) {
        SetError("SMB profile arguments are invalid");
        return result;
    }
    if (argc >= 5 && !ReadOptionalStringArg(env, argv[4], &username)) {
        SetError("SMB username must be a string");
        return result;
    }
    if (argc >= 6 && !ReadOptionalStringArg(env, argv[5], &password)) {
        SetError("SMB password must be a string");
        return result;
    }
    if (argc >= 7 && !ReadOptionalStringArg(env, argv[6], &path)) {
        SetError("SMB path must be a string");
        return result;
    }

    if (host.empty() || share.empty()) {
        SetError("SMB host and share are required");
        return result;
    }

    g_smb_state.profile_name = profile_name;
    g_smb_state.host = host;
    g_smb_state.port = port > 0 ? port : 445;
    g_smb_state.share = share;
    g_smb_state.username = username;
    g_smb_state.path = path.empty() ? "/" : path;
    g_smb_state.last_error.clear();
    g_smb_state.session_state = "configured";
    DispatchEventToJs("configured", "SMB profile configured");
    napi_create_int32(env, 0, &result);
    return result;
}

napi_value ListDirectory(napi_env env, napi_callback_info info)
{
    napi_value result = nullptr;
    napi_create_array_with_length(env, 0, &result);
    if (g_smb_state.host.empty() || g_smb_state.share.empty()) {
        SetError("SMB profile is not configured");
        return result;
    }
    g_smb_state.session_state = "listing";
    g_smb_state.last_error = kSmbBlocker;
    DispatchEventToJs("listing", kSmbBlocker);
    g_smb_state.session_state = "blocked";
    DispatchEventToJs("blocked", kSmbBlocker);
    return result;
}

napi_value OpenFile(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    std::string path;
    napi_value result = nullptr;
    napi_create_string_utf8(env, "", NAPI_AUTO_LENGTH, &result);
    if (argc < 1 || !ReadOptionalStringArg(env, argv[0], &path) || path.empty()) {
        SetError("SMB target path is required");
        return result;
    }
    g_smb_state.path = path;
    g_smb_state.session_state = "opening";
    g_smb_state.last_error = kSmbBlocker;
    DispatchEventToJs("opening", kSmbBlocker);
    g_smb_state.session_state = "blocked";
    DispatchEventToJs("blocked", kSmbBlocker);
    return result;
}

napi_value Release(napi_env env, napi_callback_info info)
{
    g_smb_state = SmbBridgeState();
    DispatchEventToJs("released", "SMB session released");
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
        {"configureProfile", nullptr, ConfigureProfile, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"listDirectory", nullptr, ListDirectory, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"openFile", nullptr, OpenFile, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"release", nullptr, Release, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

} // namespace

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
