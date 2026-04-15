#include <node_api.h>
#include <string>

namespace {

napi_value MakeString(napi_env env, const char* value)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, value, NAPI_AUTO_LENGTH, &result);
    return result;
}

napi_value GetCapability(napi_env env, napi_callback_info info)
{
    napi_value obj = nullptr;
    napi_create_object(env, &obj);

    napi_value available = nullptr;
    napi_get_boolean(env, false, &available);
    napi_set_named_property(env, obj, "available", available);

    napi_set_named_property(env, obj, "version", MakeString(env, "0.1.0-stub"));

    napi_value features = nullptr;
    napi_create_array_with_length(env, 3, &features);
    napi_set_element(env, features, 0, MakeString(env, "bridge-skeleton"));
    napi_set_element(env, features, 1, MakeString(env, "prepare-playback-pipeline"));
    napi_set_element(env, features, 2, MakeString(env, "surface-render-target"));
    napi_set_named_property(env, obj, "features", features);
    return obj;
}

napi_value Prepare(napi_env env, napi_callback_info info)
{
    napi_value result = nullptr;
    napi_create_int32(env, 0, &result);
    return result;
}

napi_value Noop(napi_env env, napi_callback_info info)
{
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"getCapability", nullptr, GetCapability, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"prepare", nullptr, Prepare, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"play", nullptr, Noop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pause", nullptr, Noop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, Noop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"seek", nullptr, Noop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"release", nullptr, Noop, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

} // namespace

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)

