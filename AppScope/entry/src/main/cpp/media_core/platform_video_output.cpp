#include "platform_outputs.h"

#include <algorithm>
#include <cstring>
#include <memory>
#include <string>

#include "video_converter.h"

#if PLAYER_SIRIUS_HAS_OH_NATIVE_WINDOW
#include <sys/mman.h>
#include <unistd.h>

#include <native_window/external_window.h>
#endif

namespace player_sirius {

#if PLAYER_SIRIUS_HAS_OH_NATIVE_WINDOW
namespace {

constexpr int32_t kDefaultBufferFormat = 0x16;

class HarmonyNativeWindowRenderer final : public Renderer {
public:
    const char* Name() const override
    {
        return "harmony-native-window-renderer";
    }

    bool Configure(const SourceSpec& source, std::string* error) override
    {
        Close();
        source_ = source;
        if (source.surface_id.empty()) {
            if (error != nullptr) {
                *error = "surfaceId is empty";
            }
            return false;
        }
        const int32_t rc = OH_NativeWindow_CreateNativeWindowFromSurfaceId(source.surface_id.c_str(), &window_);
        if (rc != 0 || window_ == nullptr) {
            if (error != nullptr) {
                *error = "OH_NativeWindow_CreateNativeWindowFromSurfaceId failed";
            }
            return false;
        }
        return true;
    }

    bool Render(const MediaFrame& frame, std::string* error) override
    {
        if (window_ == nullptr) {
            if (error != nullptr) {
                *error = "native window is not configured";
            }
            return false;
        }
        if (!frame.video) {
            return true;
        }

        VideoPixelBuffer converted;
        if (!converter_.Convert(frame, &converted, error)) {
            return false;
        }

        OH_NativeWindow_NativeWindowHandleOpt(window_, SET_BUFFER_GEOMETRY, converted.width, converted.height);
        OH_NativeWindow_NativeWindowHandleOpt(window_, SET_FORMAT, kDefaultBufferFormat);

        OHNativeWindowBuffer* native_buffer = nullptr;
        int fence_fd = -1;
        const int32_t request_rc = OH_NativeWindow_NativeWindowRequestBuffer(window_, &native_buffer, &fence_fd);
        if (request_rc != 0 || native_buffer == nullptr) {
            if (fence_fd >= 0) {
                close(fence_fd);
            }
            if (error != nullptr) {
                *error = "OH_NativeWindow_NativeWindowRequestBuffer failed";
            }
            return false;
        }

        BufferHandle* handle = OH_NativeWindow_GetBufferHandleFromNative(native_buffer);
        if (handle == nullptr) {
            if (fence_fd >= 0) {
                close(fence_fd);
            }
            if (error != nullptr) {
                *error = "OH_NativeWindow_GetBufferHandleFromNative failed";
            }
            return false;
        }

        void* mapped = mmap(nullptr, handle->size, PROT_READ | PROT_WRITE, MAP_SHARED, handle->fd, 0);
        if (mapped == MAP_FAILED || mapped == nullptr) {
            if (fence_fd >= 0) {
                close(fence_fd);
            }
            if (error != nullptr) {
                *error = "mmap native window buffer failed";
            }
            return false;
        }

        auto* destination = static_cast<uint8_t*>(mapped);
        const uint32_t destination_stride = handle->stride;
        for (int y = 0; y < converted.height; ++y) {
            const uint8_t* source_row = converted.rgba.data() + static_cast<size_t>(y * converted.stride);
            uint8_t* destination_row = destination + static_cast<size_t>(y * destination_stride);
            std::memcpy(destination_row, source_row, static_cast<size_t>(std::min(converted.stride, static_cast<int>(destination_stride))));
        }
        munmap(mapped, handle->size);

        Region region {nullptr, 0};
        const int32_t flush_rc = OH_NativeWindow_NativeWindowFlushBuffer(window_, native_buffer, fence_fd, region);
        if (flush_rc != 0) {
            if (fence_fd >= 0) {
                close(fence_fd);
            }
            if (error != nullptr) {
                *error = "OH_NativeWindow_NativeWindowFlushBuffer failed";
            }
            return false;
        }
        last_pts_ms_ = frame.pts_ms;
        return true;
    }

    void Reset() override
    {
        last_pts_ms_ = 0;
        converter_.Reset();
    }

    void Close() override
    {
        converter_.Reset();
        last_pts_ms_ = 0;
        source_ = SourceSpec();
        if (window_ != nullptr) {
            OH_NativeWindow_DestroyNativeWindow(window_);
            window_ = nullptr;
        }
    }

private:
    SourceSpec source_;
    OHNativeWindow* window_ = nullptr;
    VideoConverter converter_;
    int64_t last_pts_ms_ = 0;
};

} // namespace
#endif

std::unique_ptr<Renderer> CreatePlatformRenderer()
{
#if PLAYER_SIRIUS_HAS_OH_NATIVE_WINDOW
    return std::make_unique<HarmonyNativeWindowRenderer>();
#else
    return nullptr;
#endif
}

} // namespace player_sirius
