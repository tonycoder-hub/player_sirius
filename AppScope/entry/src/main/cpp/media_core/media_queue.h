#pragma once

#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <deque>
#include <mutex>

namespace player_sirius {

template <typename T>
class MediaQueue {
public:
    explicit MediaQueue(std::size_t capacity)
        : capacity_(capacity)
    {
    }

    bool Push(const T& value, std::chrono::milliseconds timeout = std::chrono::milliseconds(10))
    {
        std::unique_lock<std::mutex> lock(mutex_);
        if (!not_full_.wait_for(lock, timeout, [this]() { return closed_ || queue_.size() < capacity_; })) {
            return false;
        }
        if (closed_) {
            return false;
        }
        queue_.push_back(value);
        not_empty_.notify_one();
        return true;
    }

    bool Push(T&& value, std::chrono::milliseconds timeout = std::chrono::milliseconds(10))
    {
        std::unique_lock<std::mutex> lock(mutex_);
        if (!not_full_.wait_for(lock, timeout, [this]() { return closed_ || queue_.size() < capacity_; })) {
            return false;
        }
        if (closed_) {
            return false;
        }
        queue_.push_back(std::move(value));
        not_empty_.notify_one();
        return true;
    }

    bool Pop(T* value, std::chrono::milliseconds timeout = std::chrono::milliseconds(10))
    {
        if (value == nullptr) {
            return false;
        }
        std::unique_lock<std::mutex> lock(mutex_);
        if (!not_empty_.wait_for(lock, timeout, [this]() { return closed_ || !queue_.empty(); })) {
            return false;
        }
        if (queue_.empty()) {
            return false;
        }
        *value = std::move(queue_.front());
        queue_.pop_front();
        not_full_.notify_one();
        return true;
    }

    void Clear()
    {
        std::lock_guard<std::mutex> lock(mutex_);
        queue_.clear();
        not_full_.notify_all();
    }

    void Close()
    {
        std::lock_guard<std::mutex> lock(mutex_);
        closed_ = true;
        not_empty_.notify_all();
        not_full_.notify_all();
    }

    void Reopen()
    {
        std::lock_guard<std::mutex> lock(mutex_);
        closed_ = false;
        not_empty_.notify_all();
        not_full_.notify_all();
    }

    std::size_t Size() const
    {
        std::lock_guard<std::mutex> lock(mutex_);
        return queue_.size();
    }

    bool Empty() const
    {
        std::lock_guard<std::mutex> lock(mutex_);
        return queue_.empty();
    }

private:
    const std::size_t capacity_;
    mutable std::mutex mutex_;
    std::condition_variable not_empty_;
    std::condition_variable not_full_;
    std::deque<T> queue_;
    bool closed_ = false;
};

} // namespace player_sirius
