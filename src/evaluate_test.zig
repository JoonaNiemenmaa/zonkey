const std = @import("std");
const monkey = @import("root.zig");

const evaluate = monkey.evaluate;
const object = monkey.object;
const testing = std.testing;
const ast = monkey.ast;

const Scanner = monkey.scanner.Scanner;
const Parser = monkey.parser.Parser;
const Object = object.Object;
const Integer = object.Integer;
const Environment = object.Environment;

const ArenaAllocator = std.heap.ArenaAllocator;

test "test integers" {
    const cases = [_]struct { @"test": []const u8, expect: i64 }{
        .{ .@"test" = "5", .expect = 5 },
        .{ .@"test" = "12", .expect = 12 },
        .{ .@"test" = "-5", .expect = -5 },
        .{ .@"test" = "-12", .expect = -12 },
        .{ .@"test" = "--12", .expect = 12 },
        .{ .@"test" = "20 + 5", .expect = 25 },
        .{ .@"test" = "20 - 5", .expect = 15 },
        .{ .@"test" = "20 * 5", .expect = 100 },
        .{ .@"test" = "20 / 5", .expect = 4 },
        .{ .@"test" = "18 / 5", .expect = 3 },
        .{ .@"test" = "5 + 5 + 5 + 5 - 10", .expect = 10 },
        .{ .@"test" = "2 * 2 * 2 * 2 * 2", .expect = 32 },
        .{ .@"test" = "-50 + 100 + -50", .expect = 0 },
        .{ .@"test" = "5 * 2 + 10", .expect = 20 },
        .{ .@"test" = "5 + 2 * 10", .expect = 25 },
        .{ .@"test" = "20 + 2 * -10", .expect = 0 },
        .{ .@"test" = "50 / 2 * 2 + 10", .expect = 60 },
        .{ .@"test" = "2 * (5 + 10)", .expect = 30 },
        .{ .@"test" = "3 * 3 * 3 + 10", .expect = 37 },
        .{ .@"test" = "3 * (3 * 3) + 10", .expect = 37 },
        .{ .@"test" = "(5 + 10 * 2 + 15 / 3) * 2 + -10", .expect = 50 },
    };

    for (cases) |case| {
        var scanner: Scanner = .init(case.@"test");
        var parserArena: ArenaAllocator = .init(testing.allocator);
        var parser: Parser = .init(parserArena.allocator(), &scanner);
        var env: Environment = .init(std.testing.allocator, null);

        defer {
            env.deinit(null);
            parserArena.deinit();
        }

        const program = try parser.parseProgram();

        const result = try evaluate.evaluateProgram(program, &env);

        try testing.expect(result.* == .integer);

        switch (result.*) {
            .integer => |integer| try testing.expectEqual(case.expect, integer.value),
            else => unreachable,
        }
    }
}

test "test booleans" {
    const cases = [_]struct { @"test": []const u8, expect: *const object.Object }{
        .{ .@"test" = "false", .expect = &evaluate.FALSE },
        .{ .@"test" = "true", .expect = &evaluate.TRUE },
        .{ .@"test" = "!true", .expect = &evaluate.FALSE },
        .{ .@"test" = "!false", .expect = &evaluate.TRUE },
        .{ .@"test" = "!!true", .expect = &evaluate.TRUE },
        .{ .@"test" = "!!false", .expect = &evaluate.FALSE },
        .{ .@"test" = "!5", .expect = &evaluate.FALSE },
        .{ .@"test" = "!!5", .expect = &evaluate.TRUE },
        .{ .@"test" = "10 == 10", .expect = &evaluate.TRUE },
        .{ .@"test" = "10 == 15", .expect = &evaluate.FALSE },
        .{ .@"test" = "10 != 10", .expect = &evaluate.FALSE },
        .{ .@"test" = "10 != 15", .expect = &evaluate.TRUE },
        .{ .@"test" = "10 < 15", .expect = &evaluate.TRUE },
        .{ .@"test" = "10 > 15", .expect = &evaluate.FALSE },
        .{ .@"test" = "15 < 10", .expect = &evaluate.FALSE },
        .{ .@"test" = "15 > 10", .expect = &evaluate.TRUE },
        .{ .@"test" = "true == true", .expect = &evaluate.TRUE },
        .{ .@"test" = "false == false", .expect = &evaluate.TRUE },
        .{ .@"test" = "true == false", .expect = &evaluate.FALSE },
        .{ .@"test" = "true != false", .expect = &evaluate.TRUE },
        .{ .@"test" = "true != true", .expect = &evaluate.FALSE },
        .{ .@"test" = "(1 < 2) == true", .expect = &evaluate.TRUE },
        .{ .@"test" = "(1 < 2) == false", .expect = &evaluate.FALSE },
        .{ .@"test" = "(1 > 2) == true", .expect = &evaluate.FALSE },
        .{ .@"test" = "(1 > 2) == false", .expect = &evaluate.TRUE },
    };

    for (cases) |case| {
        var scanner: Scanner = .init(case.@"test");
        var parserArena: ArenaAllocator = .init(testing.allocator);
        var parser: Parser = .init(parserArena.allocator(), &scanner);
        var env: Environment = .init(std.testing.allocator, null);

        defer {
            env.deinit(null);
            parserArena.deinit();
        }

        const program = try parser.parseProgram();

        const result = try evaluate.evaluateProgram(program, &env);

        try testing.expect(result.* == .boolean);

        testing.expectEqual(case.expect, result) catch |err| {
            std.debug.print("{s}\n", .{case.@"test"});
            std.debug.print("{} != {}\n", .{ case.expect.*, result.* });
            return err;
        };
    }
}

test "test if expression evaluation" {
    const cases = [_]struct { @"test": []const u8, expect: Object }{
        .{ .@"test" = "if (true) { 10 }", .expect = Object{ .integer = Integer{ .value = 10 } } },
        .{ .@"test" = "if (1) { 10 }", .expect = Object{ .integer = Integer{ .value = 10 } } },
        .{ .@"test" = "if (1 < 2) { 10 }", .expect = Object{ .integer = Integer{ .value = 10 } } },
        .{ .@"test" = "if (1 > 2) { 10 } else { 20 }", .expect = Object{ .integer = Integer{ .value = 20 } } },
        .{ .@"test" = "if (1 < 2) { 10 } else { 20 }", .expect = Object{ .integer = Integer{ .value = 10 } } },
        .{ .@"test" = "if (false) { 10 }", .expect = evaluate.NULL },
        .{ .@"test" = "if (1 > 2) { 10 }", .expect = evaluate.NULL },
    };

    for (cases) |case| {
        var scanner: Scanner = .init(case.@"test");
        var parserArena: ArenaAllocator = .init(testing.allocator);
        var parser: Parser = .init(parserArena.allocator(), &scanner);
        var env: Environment = .init(std.testing.allocator, null);

        defer {
            env.deinit(null);
            parserArena.deinit();
        }

        const program = try parser.parseProgram();

        const result = try evaluate.evaluateProgram(program, &env);

        try testing.expectEqualDeep(case.expect, result.*);
    }
}

test "test return statements" {
    const cases = [_]struct { @"test": []const u8, expect: Object }{
        .{ .@"test" = "return 10;", .expect = Object{ .integer = Integer{ .value = 10 } } },
        .{ .@"test" = "return 10; 9;", .expect = Object{ .integer = Integer{ .value = 10 } } },
        .{ .@"test" = "return 2 * 5; 9;", .expect = Object{ .integer = Integer{ .value = 10 } } },
        .{ .@"test" = "9; return 2 * 5; 9;", .expect = Object{ .integer = Integer{ .value = 10 } } },
        .{ .@"test" =
        \\if (10 > 1) {
        \\  if (10 > 1) {
        \\    return 10;
        \\  }
        \\
        \\  return 1;
        \\}
        , .expect = Object{ .integer = Integer{ .value = 10 } } },
    };

    for (cases) |case| {
        var scanner: Scanner = .init(case.@"test");
        var parserArena: ArenaAllocator = .init(testing.allocator);
        var parser: Parser = .init(parserArena.allocator(), &scanner);
        var env: Environment = .init(std.testing.allocator, null);

        defer {
            env.deinit(null);
            parserArena.deinit();
        }

        const program = try parser.parseProgram();

        const result = try evaluate.evaluateProgram(program, &env);

        try testing.expectEqualDeep(case.expect, result.*);
    }
}

test "test error handling" {
    const cases = [_]struct { @"test": []const u8, expect: []const u8 }{
        .{
            .@"test" = "5 + true;",
            .expect = "type mismatch: integer + boolean",
        },
        .{
            .@"test" = "5 + true; 5;",
            .expect = "type mismatch: integer + boolean",
        },
        .{
            .@"test" = "-true",
            .expect = "unknown operator: -boolean",
        },
        .{
            .@"test" = "true + false;",
            .expect = "unknown operator: boolean + boolean",
        },
        .{
            .@"test" = "5; true + false; 5",
            .expect = "unknown operator: boolean + boolean",
        },
        .{
            .@"test" = "if (10 > 1) { true + false; }",
            .expect = "unknown operator: boolean + boolean",
        },
        .{
            .@"test" = "foobar",
            .expect = "identifier not found: foobar",
        },
    };

    for (cases) |case| {
        var scanner: Scanner = .init(case.@"test");
        var parserArena: ArenaAllocator = .init(testing.allocator);
        var parser: Parser = .init(parserArena.allocator(), &scanner);
        var env: Environment = .init(std.testing.allocator, null);

        defer {
            env.deinit(null);
            parserArena.deinit();
        }

        const program = try parser.parseProgram();

        const result = try evaluate.evaluateProgram(program, &env);

        switch (result.*) {
            .@"error" => |@"error"| try testing.expectEqualSlices(u8, case.expect, @"error".message),
            else => try testing.expect(false),
        }
    }
}

test "test let statements" {
    const cases = [_]struct { @"test": []const u8, expect: i64 }{
        .{ .@"test" = "let a = 5; a;", .expect = 5 },
        .{ .@"test" = "let a = 5 * 5; a;", .expect = 25 },
        .{ .@"test" = "let a = 5; let b = a; b;", .expect = 5 },
        .{ .@"test" = "let a = 5; let b = a; let c = a + b + 5; c;", .expect = 15 },
    };

    for (cases) |case| {
        var scanner: Scanner = .init(case.@"test");
        var parserArena: ArenaAllocator = .init(testing.allocator);
        var parser: Parser = .init(parserArena.allocator(), &scanner);
        var env: Environment = .init(std.testing.allocator, null);

        defer {
            env.deinit(null);
            parserArena.deinit();
        }

        const program = try parser.parseProgram();

        const result = try evaluate.evaluateProgram(program, &env);

        switch (result.*) {
            .integer => |integer| try testing.expectEqual(case.expect, integer.value),
            else => try testing.expect(false),
        }
    }
}

test "test function literals" {
    const input = "fn (x) { x + 2; }";

    var scanner: Scanner = .init(input);
    var parserArena: ArenaAllocator = .init(testing.allocator);
    var parser: Parser = .init(parserArena.allocator(), &scanner);
    var env: Environment = .init(std.testing.allocator, null);

    defer {
        env.deinit(null);
        parserArena.deinit();
    }

    const program = try parser.parseProgram();

    const result = try evaluate.evaluateProgram(program, &env);

    const expected = Object{
        .function = .{
            .body = .{
                .token = .{
                    .type = .LBRACE,
                    .line = 1,
                    .column = 8,
                    .literal = "{",
                },
                .statements = &[_]ast.Statement{
                    ast.Statement{
                        .expressionStatement = .{
                            .token = .{
                                .type = .IDENT,
                                .line = 1,
                                .column = 10,
                                .literal = "x",
                            },
                            .expression = &ast.Expression{
                                .infix = .{
                                    .token = .{
                                        .type = .PLUS,
                                        .line = 1,
                                        .column = 12,
                                        .literal = "+",
                                    },
                                    .operator = .ADD,
                                    .left = &ast.Expression{
                                        .identifier = .{
                                            .token = .{
                                                .type = .IDENT,
                                                .line = 1,
                                                .column = 10,
                                                .literal = "x",
                                            },
                                            .name = "x",
                                        },
                                    },
                                    .right = &ast.Expression{
                                        .integer = .{
                                            .token = .{
                                                .type = .INT,
                                                .line = 1,
                                                .column = 14,
                                                .literal = "2",
                                            },
                                            .value = 2,
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
            .parameters = &[_]ast.Identifier{
                ast.Identifier{
                    .token = .{
                        .type = .IDENT,
                        .line = 1,
                        .column = 5,
                        .literal = "x",
                    },
                    .name = "x",
                },
            },
            .env = &env,
        },
    };
    _ = result;
    _ = expected;

    //try testing.expectEqualDeep(expected, result.*);
}

test "test function evaluation" {
    const cases = [_]struct { @"test": []const u8, expect: i64 }{
        .{ .@"test" = "let identity = fn(x) { x; }; identity(5);", .expect = 5 },
        .{ .@"test" = "let identity = fn(x) { return x; }; identity(5);", .expect = 5 },
        .{ .@"test" = "let double = fn(x) { x * 2; }; double(5);", .expect = 10 },
        .{ .@"test" = "let add = fn(x, y) { x + y; }; add(5, 5);", .expect = 10 },
        .{ .@"test" = "let add = fn(x, y) { x + y; }; add(5 + 5, add(5, 5));", .expect = 20 },
        .{ .@"test" = "fn(x) { x; }(5)", .expect = 5 },
    };

    for (cases) |case| {
        var scanner: Scanner = .init(case.@"test");
        var parserArena: ArenaAllocator = .init(testing.allocator);
        var parser: Parser = .init(parserArena.allocator(), &scanner);
        var env: Environment = .init(std.testing.allocator, null);

        defer {
            env.deinit(null);
            parserArena.deinit();
        }

        const program = try parser.parseProgram();

        const result = try evaluate.evaluateProgram(program, &env);

        switch (result.*) {
            .integer => |integer| try testing.expectEqual(case.expect, integer.value),
            else => try testing.expect(false),
        }
    }
}
