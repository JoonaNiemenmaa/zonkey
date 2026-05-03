const std = @import("std");
const monkey = @import("root.zig");

pub fn main() !void {
    try monkey.repl.startRepl();
}
