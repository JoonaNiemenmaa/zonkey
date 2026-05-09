const std = @import("std");
const monkey = @import("root.zig");

const DebugAllocator = std.heap.DebugAllocator;
const ArenaAllocator = std.heap.ArenaAllocator; const Reader = std.Io.Reader;
const Writer = std.Io.Writer;
const File = std.Io.File;
const Io = std.Io;

const Scanner = monkey.scanner.Scanner;
const Parser = monkey.parser.Parser;
const Evaluator = monkey.evaluate.Evaluator;
const Environment = monkey.object.Environment;

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

    var debugAllocator: DebugAllocator(.{}) = .init;
    defer std.debug.print("{}\n", .{ debugAllocator.deinit() });

    const gpa = debugAllocator.allocator();

    var threaded: std.Io.Threaded = .init(gpa, .{});
    const io = threaded.io();

    var stdoutBuf: [BUFFER_SIZE]u8 = undefined;
    var stdoutWriter = File.stdout().writer(io, &stdoutBuf);
    const stdout: *Writer = &stdoutWriter.interface;

    var stdinBuf: [BUFFER_SIZE]u8 = undefined;
    var stdinReader = File.stdin().reader(io, &stdinBuf);
    const stdin: *Reader = &stdinReader.interface;

    try stdout.print("Hello user! This is the Monkey programming language!\n", .{});
    try stdout.print("Feel free to type in commands\n", .{});

    var envArena: ArenaAllocator = .init(gpa);
    defer envArena.deinit();

    var env: Environment = .init(envArena.allocator());
    defer env.deinit();

    const evaluator: Evaluator = .init(gpa);

    while (true) {
        var parserArena: ArenaAllocator = .init(gpa);
        defer parserArena.deinit();

        const arena = parserArena.allocator();

        try stdout.print(">> ", .{});
        try stdout.flush();

        const input = try stdin.takeDelimiter('\n') orelse return;

        var scanner: Scanner = .init(input);

        var parser: Parser = .init(arena, &scanner);

        const program = try parser.parseProgram();

        const errors = try parser.errors.toOwnedSlice(arena);

        if (errors.len == 0) {
            const result = try evaluator.evaluateProgram(program, &env);
            try result.print(stdout);
            evaluator.destroyObject(result);
        } else {
            try printParserErrors(stdout, errors);
        }

        try stdout.flush();
    }
}
