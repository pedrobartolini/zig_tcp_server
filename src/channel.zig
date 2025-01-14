const std = @import("std");

pub fn Channel(comptime T: type, comptime size: usize) type {
    return struct {
        queue: [size]T,
        head: usize,
        tail: usize,
        count: usize,
        mutex: std.Thread.Mutex,
        signal: std.Thread.Condition,

        pub fn init() Channel(T, size) {
            return Channel(T, size){
                .queue = undefined,
                .head = 0,
                .tail = 0,
                .count = 0,
                .mutex = .{},
                .signal = .{},
            };
        }

        pub fn rx(self: *Channel(T, size)) Rx {
            return Rx{ .chann = self };
        }

        pub const Rx = struct {
            chann: *Channel(T, size),

            pub fn receive(self: *Rx) T {
                const channel = self.chann;

                channel.mutex.lock();
                defer channel.mutex.unlock();

                if (channel.count == 0) {
                    channel.signal.wait(&channel.mutex);
                }

                const value = channel.queue[channel.head];
                channel.head = (channel.head + 1) % size;
                channel.count -= 1;

                defer channel.signal.signal();

                return value;
            }

            pub fn try_receive(self: *Rx) !T {
                const channel = self.chann;

                channel.mutex.lock();
                defer channel.mutex.unlock();

                if (channel.count == 0) {
                    return error.ChannelEmpty;
                }

                const value = channel.queue[channel.head];
                channel.head = (channel.head + 1) % size;
                channel.count -= 1;

                defer channel.signal.signal();

                return value;
            }
        };

        pub fn tx(self: *Channel(T, size)) Tx {
            return Tx{ .chann = self };
        }

        pub const Tx = struct {
            chann: *Channel(T, size),

            pub fn send(self: *Tx, value: T) void {
                const channel = self.chann;

                channel.mutex.lock();
                defer channel.mutex.unlock();

                if (channel.count == size) {
                    channel.signal.wait(&channel.mutex);
                }

                channel.queue[channel.tail] = value;
                channel.tail = (channel.tail + 1) % size;
                channel.count += 1;

                channel.signal.signal();
            }

            pub fn try_send(self: *Tx, value: T) !void {
                const channel = self.chann;

                channel.mutex.lock();
                defer channel.mutex.unlock();

                if (channel.count == size) {
                    return error.ChannelFull;
                }

                channel.queue[channel.tail] = value;
                channel.tail = (channel.tail + 1) % size;
                channel.count += 1;

                channel.signal.signal();
            }
        };
    };
}
