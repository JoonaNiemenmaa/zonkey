const std = @import("std");
const monkey = @import("root.zig");

const Init = std.process.Init;

pub fn main(init: Init) !void {
    try monkey.repl.startRepl(init.io);
}
