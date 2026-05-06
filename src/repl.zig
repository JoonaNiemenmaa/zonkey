const std = @import("std");
const monkey = @import("root.zig");

const DebugAllocator = std.heap.DebugAllocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Reader = std.io.Reader;
const Writer = std.io.Writer;

const Scanner = monkey.scanner.Scanner;
const Parser = monkey.parser.Parser;
const Evaluator = monkey.evaluate.Evaluator;

const BUFFER_SIZE = 256;

const MONKEY_FACE = 
    \\           __,__
    \\  .--.  .-"     "-.  .--.
    \\ / .. \/  .-. .-.  \/ .. \
    \\| |  '|  /   Y   \  |'  | |
    \\| \   \  \ 0 | 0 /  /   / |
    \\ \ '- ,\.-"""""""-./, -' /
    \\  ''-' /_   ^ ^   _\ '-''
    \\      |  \._   _./  |
    \\      \   \ '~' /   /
    \\       '._ '-=-' _.'
    \\          '-----'
;

fn printParserErrors(writer: *Writer, errors: [][]const u8) !void {
    try writer.print("{s}\n", .{ MONKEY_FACE });
    try writer.print("Woops! We ran into some monkey business here!\n", .{});
    try writer.print("  parser errors:\n", .{});

    for (errors) |@"error"| try writer.print("    {s}\n", .{ @"error" }); 
}

pub fn startRepl() !void {
    var stdoutBuf: [BUFFER_SIZE]u8 = undefined;
    var stdoutWriter = std.fs.File.stdout().writer(&stdoutBuf);
    const stdout: *Writer = &stdoutWriter.interface;

    var stdinBuf: [BUFFER_SIZE]u8 = undefined;
    var stdinReader = std.fs.File.stdin().reader(&stdinBuf);
    const stdin: *Reader = &stdinReader.interface;

    try stdout.print("Hello user! This is the Monkey programming language!\n", .{});
    try stdout.print("Feel free to type in commands\n", .{});

    var debugAllocator: DebugAllocator(.{}) = .init;
    defer std.debug.print("{}\n", .{ debugAllocator.deinit() });

    const gpa = debugAllocator.allocator();

    while (true) {
        var arenaAllocator: ArenaAllocator = .init(gpa);
        defer arenaAllocator.deinit();

        const arena = arenaAllocator.allocator();

        try stdout.print(">> ", .{});
        try stdout.flush();

        const input = try stdin.takeDelimiter('\n') orelse return;

        var scanner: Scanner = .init(input);

        var parser: Parser = .init(arena, &scanner);

        const program = try parser.parseProgram();

        const errors = try parser.errors.toOwnedSlice(arena);

        if (errors.len == 0) {
            const evaluator: Evaluator = .init(gpa);

            const result = try evaluator.evaluateProgram(program);

            try result.print(stdout);
            switch (result.*) {
                .integer => gpa.destroy(result),
                else => {},
            }
        } else {
            try printParserErrors(stdout, errors);
        }

        try stdout.flush();
    }
}
