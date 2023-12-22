const std = @import("std");
const os = std.os;
const fs = std.fs;
const time = std.time;

// Without Libc - Musl c port
// fn shmOpen(name: [:0]const u8, comptime flag: comptime_int, mode: std.c.mode_t) !usize {
//     const builtin = @import("builtin");
//
//     if (builtin.os.tag != .linux) {
//         return error.Unimplemented;
//     }
//
//     if (std.mem.containsAtLeast(u8, name, 1, "/") and (name.len <= 2 and name[0] == '.' and name[name.len - 1] == '.')) {
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
//         return switch (std.c.getErrno(rc)) {
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
// fn shmOpen(name: [*:0]const u8, flag: c_int, mode: std.c.mode_t) !c_int {
//     const rc = std.c.shm_open(name, flag, mode);
//     if (rc < 0) {
//         return switch (std.c.getErrno(rc)) {
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

    // Open shared memory
    // Not backed by a file - a new, uninitialized anonymous mapping
    const data = try os.mmap(null, 1024, os.PROT.READ | os.PROT.WRITE, os.MAP.SHARED | os.MAP.ANONYMOUS, -1, 0);
    defer os.munmap(data);

    // Or - if we need persistence
    // ---
    // const fd = std.c.shm_open("/execution_time", os.O.CREAT | os.O.RDWR, 0o666);
    // if (fd == -1) {
    //     return error.shm_open_error;
    // }
    // --- Or - we can build our own wrappers
    // const fd = try shmOpen("/execution_time", os.O.CREAT | os.O.RDWR, 0o666);
    // ---
    // defer _ = std.c.shm_unlink("/execution_time");
    // if (std.c.ftruncate(@intCast(fd), 1024) == -1) {
    //     return error.ftruncate_error;
    // }
    // const data = try os.mmap(null, 1024, os.PROT.READ | os.PROT.WRITE, os.MAP.SHARED, @intCast(fd), 0);
    // defer os.munmap(data);

    const pid = try os.fork();

    if (pid == 0) {
        // Child
        const start_time = time.milliTimestamp();

        var mem_stream = std.io.fixedBufferStream(data);
        const stream = mem_stream.writer();
        _ = try stream.writeInt(i64, start_time, std.builtin.Endian.little);

        // Used for testing
        // time.sleep(1e+9);

        const result = os.execvpeZ(os.argv[1], @ptrCast(os.argv[1..]), &[_:null]?[*:0]u8{null});
        // Unreachable - error if this occurs
        try stdout.print("[ERROR] {}\n", .{result});
        os.exit(1);
    } else {
        // Parent
        // Wait for child to finish executing
        const result = os.waitpid(pid, 0);
        try stdout.print("result {}\n", .{result.status});

        if (result != 0) {
            return error.ChildError;
        }

        // Record end time
        const end_time = time.milliTimestamp();

        // Read from shared memory
        var mem_stream = std.io.fixedBufferStream(data);
        const stream = mem_stream.reader();
        const start_time = try stream.readInt(i64, std.builtin.Endian.little);

        try stdout.print("{s} took {d} milliseconds to run\n", .{ os.argv[1], end_time - start_time });
    }
}
