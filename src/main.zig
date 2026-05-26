const std = @import("std");
const monkey = @import("root.zig");

const Scanner = monkey.scanner.Scanner;
const Parser = monkey.parser.Parser;
const Environment = monkey.object.Environment;

const File = std.Io.File;

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();

    _ = args.next();

    if (args.next()) |filename| {
        try monkey.repl.evaluateFile(init.io, filename);
    } else {
        try monkey.repl.startRepl();
    }
}
