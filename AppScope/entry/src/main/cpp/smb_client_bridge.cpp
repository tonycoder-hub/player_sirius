#include <node_api.h>

#include <cstdint>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#if PLAYER_SIRIUS_HAS_LIBSMB2
#include <fcntl.h>
#include <smb2/smb2.h>
#include <smb2/libsmb2.h>
#endif

namespace {

#if PLAYER_SIRIUS_HAS_LIBSMB2
constexpr const char* kSmbBackendName = "libsmb2-linked";
constexpr const char* kSmbBlocker = "";
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

struct SmbSessionConfig {
    std::string profile_name;
    std::string host;
    int32_t port = 445;
    std::string share;
    std::string username;
    std::string password;
    std::string path = "/";
};

#if PLAYER_SIRIUS_HAS_LIBSMB2
struct ActiveSmbSession {
    smb2_context* context = nullptr;
    std::string host;
    int32_t port = 445;
    std::string share;
    std::string username;
    std::string password;
};
#endif

SmbBridgeState g_smb_state;
SmbSessionConfig g_smb_config;
napi_env g_listener_env = nullptr;
napi_ref g_listener_ref = nullptr;
#if PLAYER_SIRIUS_HAS_LIBSMB2
ActiveSmbSession g_active_session;
#endif

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

std::string NormalizeRemotePath(const std::string& value)
{
    if (value.empty() || value == "/") {
        return "";
    }
    std::string normalized = value;
    for (char& ch : normalized) {
        if (ch == '\\') {
            ch = '/';
        }
    }
    while (!normalized.empty() && normalized.front() == '/') {
        normalized.erase(normalized.begin());
    }
    return normalized;
}

std::string JoinPath(const std::string& base, const std::string& leaf)
{
    if (base.empty()) {
        return leaf;
    }
    if (leaf.empty()) {
        return base;
    }
    if (base.back() == '/') {
        return base + leaf;
    }
    return base + "/" + leaf;
}

std::string SanitizeFileName(const std::string& name)
{
    std::string sanitized;
    sanitized.reserve(name.size());
    for (char ch : name) {
        if ((ch >= 'a' && ch <= 'z') ||
            (ch >= 'A' && ch <= 'Z') ||
            (ch >= '0' && ch <= '9') ||
            ch == '.' || ch == '_' || ch == '-') {
            sanitized.push_back(ch);
        } else {
            sanitized.push_back('_');
        }
    }
    if (sanitized.empty()) {
        return "smb_media.bin";
    }
    return sanitized;
}

std::string BuildCachePath(const std::string& cache_dir, const std::string& suggested_name)
{
    namespace fs = std::filesystem;
    fs::path target_dir = fs::path(cache_dir) / "smb_cache";
    std::error_code ec;
    fs::create_directories(target_dir, ec);
    fs::path file_name = SanitizeFileName(suggested_name);
    fs::path final_name = std::to_string(static_cast<long long>(std::time(nullptr))) + "_" + file_name.string();
    return (target_dir / final_name).string();
}

napi_value CreateCapabilityObject(napi_env env)
{
    napi_value obj = nullptr;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "available", MakeBoolean(env, PLAYER_SIRIUS_HAS_LIBSMB2 == 1));
    napi_set_named_property(env, obj, "version", MakeString(env, "0.2.0-smb-bridge"));
    napi_set_named_property(env, obj, "backendName", MakeString(env, kSmbBackendName));
    napi_set_named_property(env, obj, "blocker", MakeString(env, kSmbBlocker));
    napi_value features = nullptr;
    napi_create_array_with_length(env, 6, &features);
    napi_set_element(env, features, 0, MakeString(env, "profile-validation"));
    napi_set_element(env, features, 1, MakeString(env, "session-state"));
    napi_set_element(env, features, 2, MakeString(env, "native-dependency-slot"));
    napi_set_element(env, features, 3, MakeString(env, "directory-listing"));
    napi_set_element(env, features, 4, MakeString(env, "download-to-cache"));
    napi_set_element(env, features, 5, MakeString(env, "event-bridge"));
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

napi_value CreateEntryObject(
    napi_env env,
    const std::string& name,
    const std::string& path,
    bool is_directory,
    int64_t size,
    int64_t modified_at)
{
    napi_value obj = nullptr;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "name", MakeString(env, name));
    napi_set_named_property(env, obj, "path", MakeString(env, path));
    napi_set_named_property(env, obj, "isDirectory", MakeBoolean(env, is_directory));
    napi_set_named_property(env, obj, "size", MakeInt64(env, size));
    napi_set_named_property(env, obj, "modifiedAt", MakeInt64(env, modified_at));
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

#if PLAYER_SIRIUS_HAS_LIBSMB2
void ResetSession()
{
    if (g_active_session.context != nullptr) {
        smb2_disconnect_share(g_active_session.context);
        smb2_destroy_context(g_active_session.context);
    }
    g_active_session = ActiveSmbSession();
}

std::string GetLibError(smb2_context* context, const std::string& fallback)
{
    if (context == nullptr) {
        return fallback;
    }
    const char* message = smb2_get_error(context);
    return message != nullptr && message[0] != '\0' ? std::string(message) : fallback;
}

bool EnsureConnected(std::string* error)
{
    if (g_smb_config.host.empty() || g_smb_config.share.empty()) {
        if (error != nullptr) {
            *error = "SMB profile is not configured";
        }
        return false;
    }
    if (g_smb_config.port != 445) {
        if (error != nullptr) {
            *error = "当前 libsmb2 bridge 仅支持 445 端口";
        }
        return false;
    }
    if (g_active_session.context != nullptr &&
        g_active_session.host == g_smb_config.host &&
        g_active_session.port == g_smb_config.port &&
        g_active_session.share == g_smb_config.share &&
        g_active_session.username == g_smb_config.username &&
        g_active_session.password == g_smb_config.password) {
        return true;
    }

    ResetSession();
    g_smb_state.session_state = "connecting";
    g_smb_state.last_error.clear();
    DispatchEventToJs("connecting", "Connecting to SMB share");

    smb2_context* context = smb2_init_context();
    if (context == nullptr) {
        if (error != nullptr) {
            *error = "libsmb2 failed to initialize context";
        }
        return false;
    }

    if (!g_smb_config.username.empty()) {
        smb2_set_user(context, g_smb_config.username.c_str());
    }
    if (!g_smb_config.password.empty()) {
        smb2_set_password(context, g_smb_config.password.c_str());
    }

    const int rc = smb2_connect_share(
        context,
        g_smb_config.host.c_str(),
        g_smb_config.share.c_str(),
        g_smb_config.username.empty() ? nullptr : g_smb_config.username.c_str());
    if (rc != 0) {
        const std::string message = GetLibError(context, "SMB connect_share failed");
        smb2_destroy_context(context);
        if (error != nullptr) {
            *error = message;
        }
        return false;
    }

    g_active_session.context = context;
    g_active_session.host = g_smb_config.host;
    g_active_session.port = g_smb_config.port;
    g_active_session.share = g_smb_config.share;
    g_active_session.username = g_smb_config.username;
    g_active_session.password = g_smb_config.password;
    g_smb_state.session_state = "connected";
    DispatchEventToJs("connected", "SMB share connected");
    return true;
}

bool IsDirectoryEntry(const smb2dirent* entry)
{
#ifdef SMB2_TYPE_DIRECTORY
    return entry != nullptr && entry->st.smb2_type == SMB2_TYPE_DIRECTORY;
#else
    return false;
#endif
}
#endif

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

#if PLAYER_SIRIUS_HAS_LIBSMB2
    if (g_active_session.context != nullptr &&
        (g_active_session.host != host || g_active_session.share != share ||
         g_active_session.username != username || g_active_session.password != password ||
         g_active_session.port != (port > 0 ? port : 445))) {
        ResetSession();
    }
#endif

    g_smb_config.profile_name = profile_name;
    g_smb_config.host = host;
    g_smb_config.port = port > 0 ? port : 445;
    g_smb_config.share = share;
    g_smb_config.username = username;
    g_smb_config.password = password;
    g_smb_config.path = path.empty() ? "/" : path;

    g_smb_state.profile_name = g_smb_config.profile_name;
    g_smb_state.host = g_smb_config.host;
    g_smb_state.port = g_smb_config.port;
    g_smb_state.share = g_smb_config.share;
    g_smb_state.username = g_smb_config.username;
    g_smb_state.path = g_smb_config.path;
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

#if !PLAYER_SIRIUS_HAS_LIBSMB2
    g_smb_state.session_state = "blocked";
    g_smb_state.last_error = kSmbBlocker;
    DispatchEventToJs("blocked", kSmbBlocker);
    return result;
#else
    std::string error;
    if (!EnsureConnected(&error)) {
        SetError(error);
        return result;
    }

    const std::string remote_path = NormalizeRemotePath(g_smb_state.path);
    g_smb_state.session_state = "listing";
    g_smb_state.last_error.clear();
    DispatchEventToJs("listing", remote_path.empty() ? "/" : remote_path);

    smb2dir* directory = smb2_opendir(g_active_session.context, remote_path.c_str());
    if (directory == nullptr) {
        SetError(GetLibError(g_active_session.context, "SMB opendir failed"));
        return result;
    }

    uint32_t index = 0;
    while (true) {
        smb2dirent* entry = smb2_readdir(g_active_session.context, directory);
        if (entry == nullptr) {
            break;
        }
        const std::string name = entry->name != nullptr ? std::string(entry->name) : std::string();
        if (name.empty() || name == "." || name == "..") {
            continue;
        }
        const bool is_directory = IsDirectoryEntry(entry);
        const std::string full_path = "/" + JoinPath(remote_path, name);
        const int64_t size = static_cast<int64_t>(entry->st.smb2_size);
        const int64_t modified_at = static_cast<int64_t>(entry->st.smb2_mtime);
        napi_set_element(env, result, index++, CreateEntryObject(env, name, full_path, is_directory, size, modified_at));
    }
    smb2_closedir(g_active_session.context, directory);
    g_smb_state.session_state = "listed";
    DispatchEventToJs("listed", "SMB directory listed");
    return result;
#endif
}

napi_value OpenFile(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value argv[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    std::string path;
    std::string cache_dir;
    std::string suggested_name;
    napi_value result = nullptr;
    napi_create_string_utf8(env, "", NAPI_AUTO_LENGTH, &result);
    if (argc < 3 ||
        !ReadOptionalStringArg(env, argv[0], &path) ||
        !ReadOptionalStringArg(env, argv[1], &cache_dir) ||
        !ReadOptionalStringArg(env, argv[2], &suggested_name) ||
        path.empty() || cache_dir.empty()) {
        SetError("SMB target path and cache directory are required");
        return result;
    }
    g_smb_state.path = path;

#if !PLAYER_SIRIUS_HAS_LIBSMB2
    g_smb_state.session_state = "blocked";
    g_smb_state.last_error = kSmbBlocker;
    DispatchEventToJs("blocked", kSmbBlocker);
    return result;
#else
    std::string error;
    if (!EnsureConnected(&error)) {
        SetError(error);
        return result;
    }

    const std::string remote_path = NormalizeRemotePath(path);
    const std::string local_path = BuildCachePath(cache_dir, suggested_name);
    g_smb_state.session_state = "downloading";
    g_smb_state.last_error.clear();
    DispatchEventToJs("downloading", remote_path);

    smb2fh* handle = smb2_open(g_active_session.context, remote_path.c_str(), O_RDONLY);
    if (handle == nullptr) {
        SetError(GetLibError(g_active_session.context, "SMB open failed"));
        return result;
    }

    std::ofstream output(local_path, std::ios::binary | std::ios::trunc);
    if (!output.is_open()) {
        smb2_close(g_active_session.context, handle);
        SetError("Failed to create SMB cache file");
        return result;
    }

    std::vector<uint8_t> buffer(64 * 1024, 0);
    while (true) {
        const int bytes_read = smb2_read(g_active_session.context, handle, buffer.data(), static_cast<uint32_t>(buffer.size()));
        if (bytes_read < 0) {
            output.close();
            smb2_close(g_active_session.context, handle);
            std::error_code ec;
            std::filesystem::remove(local_path, ec);
            SetError(GetLibError(g_active_session.context, "SMB read failed"));
            return result;
        }
        if (bytes_read == 0) {
            break;
        }
        output.write(reinterpret_cast<const char*>(buffer.data()), bytes_read);
        if (!output.good()) {
            output.close();
            smb2_close(g_active_session.context, handle);
            std::error_code ec;
            std::filesystem::remove(local_path, ec);
            SetError("Failed to write SMB cache file");
            return result;
        }
    }

    output.close();
    smb2_close(g_active_session.context, handle);
    g_smb_state.session_state = "downloaded";
    DispatchEventToJs("downloaded", local_path);
    napi_create_string_utf8(env, std::string("file://" + local_path).c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
#endif
}

napi_value Release(napi_env env, napi_callback_info info)
{
#if PLAYER_SIRIUS_HAS_LIBSMB2
    ResetSession();
#endif
    g_smb_state = SmbBridgeState();
    g_smb_config = SmbSessionConfig();
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
