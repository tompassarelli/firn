//! Firn's intentionally narrow native boundary for Beagle semantic-index v1.
//!
//! Beagle remains the sole parser of `.bnix`; Firn consumes its deterministic
//! JSON document and exposes only the version and root digest needed to accept
//! that document at the first native boundary.

const std = @import("std");

pub const Index = struct {
    schema_version: []const u8,
    root_hash: []const u8,
};

var io_state: ?std.Io.Threaded = null;

fn io() std.Io {
    if (io_state == null) {
        io_state = std.Io.Threaded.init(std.heap.page_allocator, .{});
    }
    return io_state.?.io();
}

/// Loads one semantic-index document.  A malformed, oversized, or non-v1
/// header returns null; the application decides how to present that failure.
/// The returned pointer is process-lifetime data, appropriate for Firn's
/// one-index-per-command startup model.
pub fn load(path: []const u8) ?*const Index {
    const bytes = std.Io.Dir.cwd().readFileAlloc(
        io(),
        path,
        std.heap.page_allocator,
        .limited(16 * 1024 * 1024),
    ) catch return null;
    const value = std.json.parseFromSliceLeaky(
        std.json.Value,
        std.heap.page_allocator,
        bytes,
        .{},
    ) catch return null;
    const object = switch (value) {
        .object => |entries| entries,
        else => return null,
    };
    const schema = switch (object.get("schemaVersion") orelse return null) {
        .integer => |version| if (version == 1) "firn-index/v1" else return null,
        else => return null,
    };
    const hash = switch (object.get("rootHash") orelse return null) {
        .string => |hash| hash,
        else => return null,
    };
    if (hash.len != 64) return null;
    for (hash) |byte| {
        if (!std.ascii.isHex(byte)) return null;
    }
    const index = std.heap.page_allocator.create(Index) catch return null;
    index.* = .{
        .schema_version = schema,
        .root_hash = hash,
    };
    return index;
}

pub fn schema_version(index: *const Index) []const u8 {
    return index.schema_version;
}

pub fn root_hash(index: *const Index) []const u8 {
    return index.root_hash;
}

test "loads a semantic-index v1 header" {
    const tmp = "/tmp/firn-index-host-boundary-test.json";
    defer std.Io.Dir.cwd().deleteFile(io(), tmp) catch {};
    const content =
        "{\"files\":[],\"rootHash\":\"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\",\"schemaVersion\":1}";
    {
        const file = try std.Io.Dir.cwd().createFile(io(), tmp, .{});
        defer file.close(io());
        try file.writeStreamingAll(io(), content);
    }
    const index = load(tmp) orelse return error.ExpectedIndex;
    try std.testing.expectEqualStrings("firn-index/v1", schema_version(index));
    try std.testing.expectEqualStrings("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", root_hash(index));
}
