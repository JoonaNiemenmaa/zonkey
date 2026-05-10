const std = @import("std");
const monkey = @import("root.zig");

const DebugAllocator = std.heap.DebugAllocator;
const ArenaAllocator = std.heap.ArenaAllocator; const Reader = std.Io.Reader;
const Writer = std.Io.Writer;
const File = std.Io.File;
const Io = std.Io;
const ArrayList = std.ArrayList;

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

pub fn startRepl() !void {

    var debugAllocator: DebugAllocator(.{}) = .init;

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
    var env: Environment = .init(envArena.allocator());
    var parserArena: ArenaAllocator = .init(gpa);
    var inputArena: ArenaAllocator = .init(gpa);
    var lines: ArrayList([]const u8) = .empty;

    defer {
        envArena.deinit();
        env.deinit();
        parserArena.deinit();
        inputArena.deinit();
        lines.deinit(gpa); 
        std.debug.print("{}\n", .{ debugAllocator.deinit() });
    }

    const evaluator: Evaluator = .init(gpa);

    while (true) {
        try stdout.print(">> ", .{});
        try stdout.flush();

        const buffer = try stdin.takeDelimiter('\n') orelse return;

        const input = try inputArena.allocator().alloc(u8, buffer.len);
        std.mem.copyForwards(u8, input, buffer);

        try lines.append(gpa, input);

        var scanner: Scanner = .init(input);

        var parser: Parser = .init(parserArena.allocator(), &scanner);

        const program = try parser.parseProgram();

        const errors = try parser.errors.toOwnedSlice(parserArena.allocator());

        if (errors.len == 0) {
            const result = try evaluator.evaluateProgram(program, &env);
            try result.print(stdout);
            evaluator.destroyObject(result);
        } else {
            try stdout.print("{s}\n", .{ MONKEY_FACE });
            try stdout.print("Woops! We ran into some monkey business here!\n", .{});
            try stdout.print("  parser errors:\n", .{});

            for (errors) |@"error"| try stdout.print("    {s}\n", .{ @"error" }); 
        }

        try stdout.flush();
    }
}
