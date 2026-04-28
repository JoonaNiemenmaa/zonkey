const std = @import("std");
const monkey = @import("root.zig");

const Scanner = monkey.scanner.Scanner;
const Parser = monkey.parser.Parser;
const DebugAllocator = std.heap.DebugAllocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const TokenType = monkey.scanner.TokenType;
const Reader = std.io.Reader;
const Writer = std.io.Writer;

pub fn main() !void {
    var stdoutBuf: [256]u8 = undefined;
    var stdoutWriter = std.fs.File.stdout().writer(&stdoutBuf);
    const stdout: *Writer = &stdoutWriter.interface;

    var stdinBuf: [256]u8 = undefined;
    var stdinReader = std.fs.File.stdin().reader(&stdinBuf);
    const stdin: *Reader = &stdinReader.interface;

    try stdout.print("Hello user! This is the Monkey programming language!\n", .{});
    try stdout.print("Feel free to type in commands\n", .{});

    while (true) {
        var gpa: DebugAllocator(.{}) = .init;
        var arena: ArenaAllocator = .init(gpa.allocator());
        defer arena.deinit();

        const allocator = arena.allocator();

        try stdout.print(">> ", .{});
        try stdout.flush();

        const input = try stdin.takeDelimiter('\n') orelse return;

        var scanner: Scanner = try .init(
            allocator,
            Reader.fixed(input),
        );

        var parser: Parser = try .init(allocator, &scanner);

        const program = try parser.parseProgram();

        try parser.printErrors(stdout);
        try program.printProgram(stdout);
        try stdout.flush();
    }
}
