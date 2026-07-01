const std = @import("std");
const monkey = @import("root.zig");

const DebugAllocator = std.heap.DebugAllocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;
const File = std.Io.File;
const Io = std.Io;
const ArrayList = std.ArrayList;

const Evaluator = monkey.evaluate.Evaluator;
const Scanner = monkey.scanner.Scanner;
const Parser = monkey.parser.Parser;
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

pub fn evaluateFile(io: Io, filename: []const u8) !void {
    // var debugAllocator: DebugAllocator(.{}) = .init;
    // const gpa = debugAllocator.allocator();
    // defer std.debug.print("{}\n", .{debugAllocator.deinit()});

    const gpa = std.heap.smp_allocator;

    var arenaAllocator: ArenaAllocator = .init(gpa);
    defer arenaAllocator.deinit();

    const arena = arenaAllocator.allocator();

    const file: File = try std.Io.Dir.cwd().openFile(io, filename, .{ .mode = .read_only });
    defer file.close(io);

    const stat = try file.stat(io);

    if (stat.size == 0) return;

    const code = try arena.alloc(u8, stat.size);

    _ = try file.readPositionalAll(io, code, 0);

    var stdoutBuf: [BUFFER_SIZE]u8 = undefined;
    var stdoutWriter = File.stdout().writer(io, &stdoutBuf);
    const stdout = &stdoutWriter.interface;

    var scanner: Scanner = .init(code);
    var parser: Parser = .init(arena, &scanner);

    const program = try parser.parseProgram();

    const errors = try parser.errors.toOwnedSlice(arena);

    if (errors.len == 0) {
        var evaluator = try Evaluator.init(gpa);
        defer evaluator.deinit();
        const result = try evaluator.evaluateProgram(program);
        try result.print(stdout);
        try stdout.print("\n", .{});
        result.dec(evaluator.gc);
    } else {
        try stdout.print("{s}\n", .{MONKEY_FACE});
        try stdout.print("Woops! We ran into some monkey business here!\n", .{});
        try stdout.print("  parser errors:\n", .{});

        for (errors) |@"error"| try stdout.print("    {s}\n", .{@"error"});
    }

    try stdout.flush();
}

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

    var parserArena: ArenaAllocator = .init(gpa);
    var inputArena: ArenaAllocator = .init(gpa);
    var lines: ArrayList([]const u8) = .empty;
    var evaluator = try Evaluator.init(gpa);

    defer {
        evaluator.deinit();
        parserArena.deinit();
        inputArena.deinit();
        lines.deinit(gpa);

        std.debug.print("{}\n", .{debugAllocator.deinit()});
    }

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
            const result = try evaluator.evaluateProgram(program);
            defer result.dec(evaluator.gc);

            try result.print(stdout);
            try stdout.print("\n", .{});
        } else {
            try stdout.print("{s}\n", .{MONKEY_FACE});
            try stdout.print("Woops! We ran into some monkey business here!\n", .{});
            try stdout.print("  parser errors:\n", .{});

            for (errors) |@"error"| try stdout.print("    {s}\n", .{@"error"});
        }

        try stdout.flush();
    }
}
