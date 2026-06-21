const std = @import("std");
const monkey = @import("root.zig");

const ast = monkey.ast;
const object = monkey.object;

const Object = object.Object;
const Value = object.Value;
const ArrayList = std.ArrayList;
const Environment = object.Environment;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Scanner = monkey.scanner.Scanner;
const Parser = monkey.parser.Parser;

const TRUE = object.TRUE;
const FALSE = object.FALSE;
const NULL = object.NULL;

const createObject = object.createObject;
const createIntegerObject = object.createIntegerObject;
const createStringObject = object.createStringObject;
const createErrorObject = object.createErrorObject;
const toBooleanObject = object.toBooleanObject;

pub fn evaluateProgram(program: ast.Program, env: *Environment) !*Object {
    var result: *Object = @constCast(object.NULL);
    for (program.statements, 1..) |statement, i| {
        result = try evaluateStatement(statement, env);

        switch (result.value) {
            .@"return" => |value| {
                result.dec(env.allocator);
                return value;
            },
            .@"error" => return result,
            else => {},
        }

        if (i < program.statements.len) result.dec(env.allocator);
    }
    return result;
}

fn evaluateStatement(statement: ast.Statement, env: *Environment) Allocator.Error!*Object {
    return switch (statement) {
        .expressionStatement => |expressionStatement| try evaluateExpression(expressionStatement.expression.*, env),
        .returnStatement => |returnStatement| try evaluateReturn(returnStatement, env),
        .letStatement => |letStatement| try evaluateLet(letStatement, env),
        else => unreachable,
    };
}

fn evaluateBlock(block: ast.Block, env: *Environment) !*Object {
    var result: *Object = @constCast(NULL);
    for (block.statements, 1..) |statement, i| {
        result = try evaluateStatement(statement, env);
        if (result.value == .@"return" or result.value == .@"error") return result;
        if (i < block.statements.len) result.dec(env.allocator);
    }
    return result;
}

fn evaluateReturn(statement: ast.ReturnStatement, env: *Environment) !*Object {
    const result = try createObject(env.allocator);
    result.value = Value{ .@"return" = try evaluateExpression(statement.expression.*, env) };
    return result;
}

fn evaluateLet(statement: ast.LetStatement, env: *Environment) !*Object {
    const result = try evaluateExpression(statement.expression.*, env);
    if (result.value == .@"error") return result;
    try env.put(statement.identifier.name, result);
    return result;
}

fn evaluateExpression(expression: ast.Expression, env: *Environment) Allocator.Error!*Object {
    return switch (expression) {
        .identifier => |identifier| evaluateIdentifier(identifier, env),
        .integer => |integer| createIntegerObject(integer.value, env.allocator),
        .boolean => |boolean| toBooleanObject(boolean.value),
        .string => |string| createStringObject(string.value, env.allocator),
        .prefix => |prefix| evaluatePrefix(prefix, env),
        .infix => |infix| evaluateInfix(infix, env),
        .@"if" => |@"if"| evaluateIf(@"if", env),
        .function => |function| evaluateFunction(function, env),
        .call => |call| evaluateCall(call, env),
    };
}

fn evaluateCall(call: ast.Call, env: *Environment) !*Object {
    const expression = try evaluateExpression(call.function.*, env);
    defer expression.dec(env.allocator);

    const function = switch (expression.value) {
        .function => |function| function,
        .builtin => |builtin| {
            const arguments = try evaluateArguments(call.arguments, env);
            defer env.allocator.free(arguments);

            const result = try builtin(arguments, call.token, env);

            for (arguments) |argument| argument.dec(env.allocator);

            return result;
        },
        .@"error" => return expression,
        else => |value| return createErrorObject(call.token.line, call.token.column, "cannot call {s}", .{
            @tagName(value),
        }, env.allocator),
    };

    if (function.parameters.len != call.arguments.len) return createErrorObject(
        call.token.line,
        call.token.column,
        "function call provided {} arguments instead of {}",
        .{ call.arguments.len, function.parameters.len },
        env.allocator,
    );

    const arguments = try evaluateArguments(call.arguments, env);
    defer env.allocator.free(arguments);

    var innerEnv: Environment = .init(env.allocator, function.env);
    defer innerEnv.deinit();

    for (function.parameters, arguments) |parameter, argument| {
        if (argument.value == .@"error") return argument;
        try innerEnv.put(parameter.name, argument);
        argument.dec(env.allocator);
    }

    const result = try evaluateBlock(function.body, &innerEnv);

    switch (result.value) {
        .@"return" => |@"return"| {
            result.dec(env.allocator);
            return @"return";
        },
        else => return result,
    }
}

fn evaluateArguments(arguments: []*const ast.Expression, env: *Environment) ![]*Object {
    var evaluatedArguments: ArrayList(*Object) = .empty;
    errdefer evaluatedArguments.deinit(env.allocator);

    for (arguments) |argument| {
        const evaluated = try evaluateExpression(argument.*, env);
        try evaluatedArguments.append(env.allocator, evaluated);
    }

    return try evaluatedArguments.toOwnedSlice(env.allocator);
}

fn evaluateIf(@"if": ast.If, env: *Environment) !*Object {
    const condition = try evaluateExpression(@constCast(@"if".condition).*, env);

    if (condition.value == .@"error") return condition;

    defer condition.dec(env.allocator);

    if (condition != object.NULL and condition != object.FALSE) {
        return try evaluateBlock(@"if".consequence, env);
    } else {
        return if (@"if".alternative) |alternative| try evaluateBlock(alternative, env) else @constCast(object.NULL);
    }
}

fn evaluatePrefix(prefix: ast.Prefix, env: *Environment) !*Object {
    const operand = try evaluateExpression(prefix.operand.*, env);

    return switch (prefix.operator) {
        .NOT => evaluatePrefixBang(prefix.token, operand, env),
        .MINUS => evaluatePrefixMinus(prefix.token, operand, env),
    };
}

fn evaluatePrefixBang(token: monkey.token.Token, operand: *Object, env: *Environment) !*Object {
    defer operand.dec(env.allocator);
    return switch (operand.value) {
        .boolean => |boolean| toBooleanObject(!boolean),
        .null => toBooleanObject(true),
        .integer => |integer| toBooleanObject(integer == 0),
        else => createErrorObject(
            token.line,
            token.column,
            "unknown operator: {s}{s}",
            .{
                token.literal,
                @tagName(operand.value),
            },
            env.allocator,
        ),
    };
}

fn evaluatePrefixMinus(token: monkey.token.Token, operand: *Object, env: *Environment) !*Object {
    return switch (operand.value) {
        .integer => |integer| integerBlock: {
            operand.value = Value{ .integer = -integer };
            break :integerBlock operand;
        },
        else => createErrorObject(
            token.line,
            token.column,
            "unknown operator: {s}{s}",
            .{
                token.literal,
                @tagName(operand.value),
            },
            env.allocator,
        ),
    };
}

fn evaluateInfix(infix: ast.Infix, env: *Environment) !*Object {
    const left = try evaluateExpression(@constCast(infix.left).*, env);
    if (left.value == .@"error") return left;
    defer left.dec(env.allocator);

    const right = try evaluateExpression(@constCast(infix.right).*, env);
    if (right.value == .@"error") return right;
    defer right.dec(env.allocator);

    if (left.value == .integer and right.value == .integer) {
        return evaluateIntegerInfix(left, infix.operator, right, env);
    } else if (left.value == .boolean and right.value == .boolean) {
        return switch (infix.operator) {
            .EQUALS => toBooleanObject(left == right),
            .NOT_EQUALS => toBooleanObject(left != right),
            else => createErrorObject(
                infix.token.line,
                infix.token.column,
                "unknown operator: {s} {s} {s}",
                .{
                    @tagName(left.value),
                    infix.token.literal,
                    @tagName(right.value),
                },
                env.allocator,
            ),
        };
    } else if (left.value == .string and right.value == .string) {
        return evaluateStringInfix(left, infix, right, env);
    }

    return createErrorObject(
        infix.token.line,
        infix.token.column,
        "type mismatch: {s} {s} {s}",
        .{
            @tagName(left.value),
            infix.token.literal,
            @tagName(right.value),
        },
        env.allocator,
    );
}

fn evaluateStringInfix(left: *Object, infix: ast.Infix, right: *Object, env: *Environment) !*Object {
    const leftString = switch (left.value) {
        .string => |string| string,
        else => unreachable,
    };

    const rightString = switch (right.value) {
        .string => |string| string,
        else => unreachable,
    };

    return switch (infix.operator) {
        .ADD => {
            const result = try createObject(env.allocator);

            result.value = Value{
                .string = try std.mem.concat(env.allocator, u8, &.{ leftString, rightString }),
            };

            return result;
        },
        else => createErrorObject(
            infix.token.line,
            infix.token.column,
            "unknown operator: {s} {s} {s}",
            .{
                @tagName(left.value),
                infix.token.literal,
                @tagName(right.value),
            },
            env.allocator,
        ),
    };
}

fn evaluateIntegerInfix(left: *Object, operator: ast.InfixOperator, right: *Object, env: *Environment) !*Object {
    const leftInteger = switch (left.value) {
        .integer => |integer| integer,
        else => unreachable,
    };

    const rightInteger = switch (right.value) {
        .integer => |integer| integer,
        else => unreachable,
    };

    const result = switch (operator) {
        .ADD => try createIntegerObject(leftInteger + rightInteger, env.allocator),
        .SUBTRACT => try createIntegerObject(leftInteger - rightInteger, env.allocator),
        .MULTIPLY => try createIntegerObject(leftInteger * rightInteger, env.allocator),
        .DIVIDE => try createIntegerObject(@divFloor(leftInteger, rightInteger), env.allocator),

        .EQUALS => toBooleanObject(leftInteger == rightInteger),
        .NOT_EQUALS => toBooleanObject(leftInteger != rightInteger),
        .LESS_THAN => toBooleanObject(leftInteger < rightInteger),
        .GREATER_THAN => toBooleanObject(leftInteger > rightInteger),
    };

    return result;
}

fn evaluateFunction(function: ast.Function, env: *Environment) !*Object {
    const functionObject = try createObject(env.allocator);

    const value = try env.allocator.create(object.Function);

    value.body = function.body;
    value.parameters = function.parameters;
    value.env = env;

    functionObject.value = Value{ .function = value };
    return functionObject;
}

fn evaluateIdentifier(identifier: ast.Identifier, env: *Environment) !*Object {
    if (try env.get(identifier.name)) |value| return value;

    if (object.builtins.get(identifier.name)) |builtin| return @constCast(builtin);

    return try createErrorObject(
        identifier.token.line,
        identifier.token.column,
        "identifier not found: {s}",
        .{identifier.name},
        env.allocator,
    );
}

fn evaluateTestCase(input: []const u8) !*Object {
    var scanner: Scanner = .init(input);

    var arena: ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    var parser: Parser = .init(arena.allocator(), &scanner);

    const program = try parser.parseProgram();

    var env: Environment = .init(std.testing.allocator, null);
    defer env.deinit();

    return try evaluateProgram(program, &env);
}

fn expectObject(expected: *const Object, case: []const u8) !void {
    const result = try evaluateTestCase(case);
    defer result.dec(std.testing.allocator);
    try std.testing.expectEqualDeep(expected, result);
}

test "integer evaluation" {
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
        const result = try evaluateTestCase(case.@"test");

        try std.testing.expect(result.value == .integer);

        switch (result.value) {
            .integer => |integer| try std.testing.expectEqual(case.expect, integer),
            else => unreachable,
        }

        result.dec(std.testing.allocator);
    }
}

test "boolean evaluation" {
    const cases = [_]struct { @"test": []const u8, expect: *const object.Object }{
        .{ .@"test" = "false", .expect = FALSE },
        .{ .@"test" = "true", .expect = TRUE },
        .{ .@"test" = "!true", .expect = FALSE },
        .{ .@"test" = "!false", .expect = TRUE },
        .{ .@"test" = "!!true", .expect = TRUE },
        .{ .@"test" = "!!false", .expect = FALSE },
        .{ .@"test" = "!5", .expect = FALSE },
        .{ .@"test" = "!!5", .expect = TRUE },
        .{ .@"test" = "10 == 10", .expect = TRUE },
        .{ .@"test" = "10 == 15", .expect = FALSE },
        .{ .@"test" = "10 != 10", .expect = FALSE },
        .{ .@"test" = "10 != 15", .expect = TRUE },
        .{ .@"test" = "10 < 15", .expect = TRUE },
        .{ .@"test" = "10 > 15", .expect = FALSE },
        .{ .@"test" = "15 < 10", .expect = FALSE },
        .{ .@"test" = "15 > 10", .expect = TRUE },
        .{ .@"test" = "true == true", .expect = TRUE },
        .{ .@"test" = "false == false", .expect = TRUE },
        .{ .@"test" = "true == false", .expect = FALSE },
        .{ .@"test" = "true != false", .expect = TRUE },
        .{ .@"test" = "true != true", .expect = FALSE },
        .{ .@"test" = "(1 < 2) == true", .expect = TRUE },
        .{ .@"test" = "(1 < 2) == false", .expect = FALSE },
        .{ .@"test" = "(1 > 2) == true", .expect = FALSE },
        .{ .@"test" = "(1 > 2) == false", .expect = TRUE },
    };

    for (cases) |case| {
        const result = try evaluateTestCase(case.@"test");

        try std.testing.expect(result.value == .boolean);

        std.testing.expectEqual(case.expect, result) catch |err| {
            std.debug.print("{s}\n", .{case.@"test"});
            std.debug.print("{} != {}\n", .{ case.expect.*, result.* });
            return err;
        };

        result.dec(std.testing.allocator);
    }
}

test "test if expression evaluation" {
    const cases = [_]struct { @"test": []const u8, expect: Value }{
        .{ .@"test" = "if (true) { 10 }", .expect = Value{ .integer = 10 } },
        .{ .@"test" = "if (1) { 10 }", .expect = Value{ .integer = 10 } },
        .{ .@"test" = "if (1 < 2) { 10 }", .expect = Value{ .integer = 10 } },
        .{ .@"test" = "if (1 > 2) { 10 } else { 20 }", .expect = Value{ .integer = 20 } },
        .{ .@"test" = "if (1 < 2) { 10 } else { 20 }", .expect = Value{ .integer = 10 } },
        .{ .@"test" = "if (false) { 10 }", .expect = NULL.value },
        .{ .@"test" = "if (1 > 2) { 10 }", .expect = NULL.value },
    };

    for (cases) |case| {
        const result = try evaluateTestCase(case.@"test");

        try std.testing.expectEqual(case.expect, result.value);

        result.dec(std.testing.allocator);
    }
}

test "test return statements" {
    const cases = [_]struct { @"test": []const u8, expect: Value }{
        .{ .@"test" = "return 10;", .expect = Value{ .integer = 10 } },
        .{ .@"test" = "return 10; 9;", .expect = Value{ .integer = 10 } },
        .{ .@"test" = "return 2 * 5; 9;", .expect = Value{ .integer = 10 } },
        .{ .@"test" = "9; return 2 * 5; 9;", .expect = Value{ .integer = 10 } },
        .{ .@"test" =
        \\if (10 > 1) {
        \\  if (10 > 1) {
        \\    return 10;
        \\  }
        \\
        \\  return 1;
        \\}
        , .expect = Value{ .integer = 10 } },
    };

    for (cases) |case| {
        const result = try evaluateTestCase(case.@"test");

        try std.testing.expectEqualDeep(case.expect, result.value);

        result.dec(std.testing.allocator);
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
        const result = try evaluateTestCase(case.@"test");

        switch (result.value) {
            .@"error" => |@"error"| try std.testing.expectEqualSlices(u8, case.expect, @"error".message),
            else => try std.testing.expect(false),
        }

        result.dec(std.testing.allocator);
    }
}

test "test let statements" {
    const cases = [_]struct { @"test": []const u8, expect: i64 }{
        .{ .@"test" = "let a = 5; a;", .expect = 5 },
        .{ .@"test" = "let a = 5 * 5; a;", .expect = 25 },
        .{ .@"test" = "let a = 5; let b = a; b;", .expect = 5 },
        .{ .@"test" = "let a = 5; let a = 10; a;", .expect = 10 },
    };

    for (cases) |case| {
        const result = try evaluateTestCase(case.@"test");

        switch (result.value) {
            .integer => |integer| try std.testing.expectEqual(case.expect, integer),
            else => try std.testing.expect(false),
        }

        result.dec(std.testing.allocator);
    }
}

test "test function literals" {
    var scanner: Scanner = .init("fn (x) { x + 2 }");

    var arena: ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    var parser: Parser = .init(arena.allocator(), &scanner);

    const program = try parser.parseProgram();

    var env: Environment = .init(std.testing.allocator, null);
    defer env.deinit();

    const result = try evaluateProgram(program, &env);

    const expected = @constCast(&object.Function{
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
    });

    try std.testing.expect(result.value == .function);

    switch (result.value) {
        .function => |function| {
            try std.testing.expectEqual(expected.env, function.env);
            try std.testing.expectEqualDeep(expected.body, function.body);
            try std.testing.expectEqualDeep(expected.parameters, function.parameters);
        },
        else => unreachable,
    }

    result.dec(std.testing.allocator);
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
        const result = try evaluateTestCase(case.@"test");

        switch (result.value) {
            .integer => |integer| try std.testing.expectEqual(case.expect, integer),
            else => try std.testing.expect(false),
        }

        result.dec(std.testing.allocator);
    }
}

test "string evaluation" {
    try expectObject(&Object{ .refs = 1, .value = .{ .string = "OLEN PARAS" } },
        \\"OLEN PARAS"
    );
    try expectObject(&Object{ .refs = 1, .value = .{ .string = "MITÄ HONGYUAN TARVITSEE?" } },
        \\"MITÄ" + " " + "HONGYUAN" + " " + "TARVITSEE?"
    );
}

test "builtin len function" {
    try expectObject(&Object{ .refs = 1, .value = .{ .integer = 0 } },
        \\len("");
    );
    try expectObject(&Object{ .refs = 1, .value = .{ .integer = 4 } },
        \\len("four");
    );
    try expectObject(&Object{ .refs = 1, .value = .{ .integer = 11 } },
        \\len("hello world");
    );
    try expectObject(&Object{
        .refs = 1,
        .value = .{
            .@"error" = @constCast(&object.Error{
                .column = 4,
                .line = 1,
                .message = "argument to 'len' not supported, got integer",
            }),
        },
    },
        \\len(1);
    );
    try expectObject(&Object{
        .refs = 1,
        .value = .{
            .@"error" = @constCast(&object.Error{
                .column = 4,
                .line = 1,
                .message = "function call provided 2 arguments instead of 1",
            }),
        },
    },
        \\len("one", "two");
    );
}
