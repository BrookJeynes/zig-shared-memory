const std = @import("std");
const os = std.os;
const fs = std.fs;
const mem = std.mem;
const c = std.c;

// Without Libc - Musl c port
// fn shmOpen(name: [:0]const u8, comptime flag: comptime_int, mode: c.mode_t) !usize {
//     const builtin = @import("builtin");
//
//     if (builtin.os.tag != .linux) {
//         return error.Unimplemented;
//     }
//
//     if (mem.containsAtLeast(u8, name, 1, "/") and (name.len <= 2 and name[0] == '.' and name[name.len - 1] == '.')) {
//         return error.OperationNotSupported;
//     }
//     if (name.len > fs.MAX_NAME_BYTES) {
//         return error.NameTooLong;
//     }
//
//     var buf: [fs.MAX_NAME_BYTES + 10:0]u8 = undefined;
//     @memcpy(buf[0..9], "/dev/shm/");
//     @memcpy(buf[9..][0..name.len], name);
//
//     const rc = os.linux.open(&buf, flag | os.O.NOFOLLOW | os.O.CLOEXEC | os.O.NONBLOCK, mode);
//     if (rc < 0) {
//         return switch (c.getErrno(rc)) {
//             .ACCES => error.PermissionDenied,
//             .EXIST => error.ObjectAlreadyExists,
//             // ...
//             else => unreachable,
//         };
//     }
//
//     return rc;
// }

// Using Libc
// fn shmOpen(name: [*:0]const u8, flag: c_int, mode: c.mode_t) !c_int {
//     const rc = c.shm_open(name, flag, mode);
//     if (rc < 0) {
//         return switch (c.getErrno(rc)) {
//             .ACCES => error.PermissionDenied,
//             .EXIST => error.ObjectAlreadyExists,
//             // ..
//             else => unreachable,
//         };
//     }
//
//     return rc;
// }

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const numbers = [_]u32{ 43, 23, 53, 82, 24, 92, 204, 18, 230, 200 };

    const raw_data = try os.mmap(null, @sizeOf(u32) * numbers.len, os.PROT.READ | os.PROT.WRITE, os.MAP.SHARED | os.MAP.ANONYMOUS, -1, 0);
    defer os.munmap(raw_data);

    // Or - if we need persistence
    // ---
    // const fd = c.shm_open("/numbers", os.O.CREAT | os.O.RDWR, 0o666);
    // if (fd == -1) {
    //     return error.shm_open_error;
    // }
    // --- Or - we can build our own wrappers
    // const fd = try shmOpen("/numbers", os.O.CREAT | os.O.RDWR, 0o666);
    // ---
    // defer _ = c.shm_unlink("/numbers");
    // if (c.ftruncate(@intCast(fd), 1024) == -1) {
    //     return error.ftruncate_error;
    // }
    // const raw_data = try os.mmap(null, @sizeOf(u32) * ARRAY_LEN, os.PROT.READ | os.PROT.WRITE, os.MAP.SHARED, @intCast(fd), 0);
    // defer os.munmap(data);

    const data: *[numbers.len]u32 = @ptrCast(raw_data);
    data.* = numbers;

    try stdout.print("[INFO] Unsorted numbers array:\n", .{});
    for (data) |num| {
        try stdout.print("- {d}\n", .{num});
    }

    const pid = try os.fork();

    if (pid == 0) {
        // Child
        mem.sort(u32, data, {}, std.sort.asc(u32));
        os.exit(0);
    } else {
        // Parent
        // Wait for child to finish executing
        const result = os.waitpid(pid, 0);
        if (result.status != 0) {
            return error.ChildError;
        }

        try stdout.print("[INFO] Sorted numbers array:\n", .{});
        for (data) |num| {
            try stdout.print("- {d}\n", .{num});
        }
    }
}
