const std = @import("std");
const monkey = @import("root.zig");

const ast = monkey.ast;
const object = monkey.object;

const Object = object.Object;
const Value = object.Value;
const Token = monkey.token.Token;
const ArrayList = std.ArrayList;
const Environment = object.Environment;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const StaticStringMap = std.StaticStringMap;

const Scanner = monkey.scanner.Scanner;
const Parser = monkey.parser.Parser;
const GarbageCollector = monkey.object.GarbageCollector;

const TRUE = object.TRUE;
const FALSE = object.FALSE;
const NULL = object.NULL;

const createObject = object.createObject;
const createIntegerObject = object.createIntegerObject;
const createStringObject = object.createStringObject;
const createErrorObject = object.createErrorObject;
const createArrayObject = object.createArrayObject;
const toBooleanObject = object.toBooleanObject;

pub const Evaluator = @This();

allocator: Allocator,
gc: GarbageCollector,
root: Environment,

builtins: StaticStringMap(*const Object) = .initComptime(.{
    .{ "len", &Object{ .value = .{ .builtin = &len } } },
    .{ "first", &Object{ .value = .{ .builtin = &first } } },
    .{ "rest", &Object{ .value = .{ .builtin = &rest } } },
    .{ "push", &Object{ .value = .{ .builtin = &push } } },
}),

pub fn init(allocator: Allocator) @This() {
    return @This(){ .allocator = allocator, .gc = .init(allocator), .root = .init(allocator, null) };
}

pub fn deinit(self: *@This()) void {
    self.root.deinit(&self.gc);
    self.gc.collect();
}

pub fn evaluateProgram(self: *@This(), program: ast.Program) !*Object {
    var result: *Object = @constCast(object.NULL);
    for (program.statements, 1..) |statement, i| {
        result = try self.evaluateStatement(statement, &self.root);

        switch (result.value) {
            .@"return" => |value| {
                result.dec(&self.gc);
                return value;
            },
            .@"error" => return result,
            else => {},
        }

        if (i < program.statements.len) result.dec(&self.gc);
    }

    self.gc.collect();

    return result;
}

fn evaluateStatement(self: *@This(), statement: ast.Statement, env: *Environment) Allocator.Error!*Object {
    return switch (statement) {
        .expressionStatement => |expressionStatement| try self.evaluateExpression(expressionStatement.expression.*, env),
        .returnStatement => |returnStatement| try self.evaluateReturn(returnStatement, env),
        .letStatement => |letStatement| try self.evaluateLet(letStatement, env),
        else => unreachable,
    };
}

fn evaluateBlock(self: *@This(), block: ast.Block, env: *Environment) !*Object {
    var result: *Object = @constCast(NULL);
    for (block.statements, 1..) |statement, i| {
        result = try self.evaluateStatement(statement, env);
        if (result.value == .@"return" or result.value == .@"error") return result;
        if (i < block.statements.len) result.dec(&self.gc);
    }
    return result;
}

fn evaluateReturn(self: *@This(), statement: ast.ReturnStatement, env: *Environment) !*Object {
    const result = try createObject(self.allocator);
    result.value = Value{ .@"return" = try self.evaluateExpression(statement.expression.*, env) };
    return result;
}

fn evaluateLet(self: *@This(), statement: ast.LetStatement, env: *Environment) !*Object {
    const result = try self.evaluateExpression(statement.expression.*, env);
    if (result.value == .@"error") return result;
    try env.put(statement.identifier.name, result, &self.gc);
    return result;
}

fn evaluateExpression(self: *@This(), expression: ast.Expression, env: *Environment) Allocator.Error!*Object {
    return switch (expression) {
        .identifier => |identifier| self.evaluateIdentifier(identifier, env),
        .integer => |integer| createIntegerObject(integer.value, self.allocator),
        .boolean => |boolean| toBooleanObject(boolean.value),
        .string => |string| createStringObject(string.value, self.allocator),
        .prefix => |prefix| self.evaluatePrefix(prefix, env),
        .infix => |infix| self.evaluateInfix(infix, env),
        .@"if" => |@"if"| self.evaluateIf(@"if", env),
        .function => |function| self.evaluateFunction(function, env),
        .call => |call| self.evaluateCall(call, env),
        .array => |array| self.evaluateArray(array, env),
        .access => |access| self.evaluateAccess(access, env),
    };
}

fn evaluateArray(self: *@This(), literal: ast.Array, env: *Environment) !*Object {
    const objects = try self.allocator.alloc(*Object, literal.items.len);
    errdefer self.allocator.free(objects);

    for (literal.items, 0..) |item, i| {
        const result = try self.evaluateExpression(item.*, env);

        if (result.value == .@"error") {
            for (objects[0..i]) |obj| obj.dec(&self.gc);
            self.allocator.free(objects);
            return result;
        }

        objects[i] = result;
    }

    const array = try createArrayObject(objects, &self.gc);

    return array;
}

fn evaluateAccess(self: *@This(), access: ast.Access, env: *Environment) !*Object {
    const collection = try self.evaluateExpression(access.collection.*, env);
    defer collection.dec(&self.gc);

    if (collection.value == .@"error") return collection;

    switch (collection.value) {
        .array => |array| {
            const index = try self.evaluateExpression(access.index.*, env);
            defer index.dec(&self.gc);

            if (index.value == .@"error") return index;

            switch (index.value) {
                .integer => |integer| {
                    if (integer >= 0 and integer < array.items.len) {
                        const obj = array.items[@intCast(integer)];
                        obj.inc();
                        return obj;
                    }

                    return createErrorObject(
                        access.token.line,
                        access.token.column,
                        "access out of bounds",
                        .{},
                        self.allocator,
                    );
                },
                else => |value| return createErrorObject(
                    access.token.line,
                    access.token.column,
                    "array index must integer, not {s}",
                    .{@tagName(value)},
                    self.allocator,
                ),
            }
        },
        else => |value| return createErrorObject(
            access.token.line,
            access.token.column,
            "{s} object is not indexable",
            .{@tagName(value)},
            self.allocator,
        ),
    }
}

fn evaluateCall(self: *@This(), call: ast.Call, env: *Environment) !*Object {
    const arguments = try self.allocator.alloc(*Object, call.arguments.len);
    defer self.allocator.free(arguments);

    for (call.arguments, 0..) |argument, i| arguments[i] = try self.evaluateExpression(argument.*, env);

    const expression = try self.evaluateExpression(call.function.*, env);

    const function = switch (expression.value) {
        .function => |function| function,
        .builtin => |builtin| {
            const result = try builtin(self, arguments, call.token);
            for (arguments) |argument| argument.dec(&self.gc);
            expression.dec(&self.gc);
            return result;
        },
        .@"error" => return expression,
        else => |value| return createErrorObject(call.token.line, call.token.column, "cannot call {s}", .{
            @tagName(value),
        }, self.allocator),
    };

    defer expression.dec(&self.gc);

    if (function.parameters.len != call.arguments.len) return createErrorObject(
        call.token.line,
        call.token.column,
        "function call provided {} arguments instead of {}",
        .{ call.arguments.len, function.parameters.len },
        self.allocator,
    );

    var innerEnv: Environment = .init(self.allocator, function.env);
    defer innerEnv.deinit(&self.gc);

    for (function.parameters, arguments) |parameter, argument| {
        if (argument.value == .@"error") return argument;
        try innerEnv.put(parameter.name, argument, &self.gc);
        argument.dec(&self.gc);
    }

    const result = try self.evaluateBlock(function.body, &innerEnv);

    switch (result.value) {
        .@"return" => |@"return"| {
            result.dec(&self.gc);
            return @"return";
        },
        else => return result,
    }
}

fn evaluateIf(self: *@This(), @"if": ast.If, env: *Environment) !*Object {
    const condition = try self.evaluateExpression(@constCast(@"if".condition).*, env);

    if (condition.value == .@"error") return condition;

    defer condition.dec(&self.gc);

    if (condition != object.NULL and condition != object.FALSE) {
        return try self.evaluateBlock(@"if".consequence, env);
    } else {
        return if (@"if".alternative) |alternative| try self.evaluateBlock(alternative, env) else @constCast(object.NULL);
    }
}

fn evaluatePrefix(self: *@This(), prefix: ast.Prefix, env: *Environment) !*Object {
    const operand = try self.evaluateExpression(prefix.operand.*, env);

    return switch (prefix.operator) {
        .NOT => self.evaluatePrefixBang(prefix.token, operand),
        .MINUS => self.evaluatePrefixMinus(prefix.token, operand),
    };
}

fn evaluatePrefixBang(self: *@This(), token: monkey.token.Token, operand: *Object) !*Object {
    defer operand.dec(&self.gc);
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
            self.allocator,
        ),
    };
}

fn evaluatePrefixMinus(self: *@This(), token: monkey.token.Token, operand: *Object) !*Object {
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
            self.allocator,
        ),
    };
}

fn evaluateInfix(self: *@This(), infix: ast.Infix, env: *Environment) !*Object {
    const left = try self.evaluateExpression(@constCast(infix.left).*, env);
    if (left.value == .@"error") return left;
    defer left.dec(&self.gc);

    const right = try self.evaluateExpression(@constCast(infix.right).*, env);
    if (right.value == .@"error") return right;
    defer right.dec(&self.gc);

    if (left.value == .integer and right.value == .integer) {
        return self.evaluateIntegerInfix(left, infix.operator, right);
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
                self.allocator,
            ),
        };
    } else if (left.value == .string and right.value == .string) {
        return self.evaluateStringInfix(left, infix, right);
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
        self.allocator,
    );
}

fn evaluateStringInfix(self: *@This(), left: *Object, infix: ast.Infix, right: *Object) !*Object {
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
            const result = try createObject(self.allocator);

            result.value = Value{
                .string = try std.mem.concat(self.allocator, u8, &.{ leftString, rightString }),
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
            self.allocator,
        ),
    };
}

fn evaluateIntegerInfix(self: *@This(), left: *Object, operator: ast.InfixOperator, right: *Object) !*Object {
    const leftInteger = switch (left.value) {
        .integer => |integer| integer,
        else => unreachable,
    };

    const rightInteger = switch (right.value) {
        .integer => |integer| integer,
        else => unreachable,
    };

    const result = switch (operator) {
        .ADD => try createIntegerObject(leftInteger + rightInteger, self.allocator),
        .SUBTRACT => try createIntegerObject(leftInteger - rightInteger, self.allocator),
        .MULTIPLY => try createIntegerObject(leftInteger * rightInteger, self.allocator),
        .DIVIDE => try createIntegerObject(@divFloor(leftInteger, rightInteger), self.allocator),

        .EQUALS => toBooleanObject(leftInteger == rightInteger),
        .NOT_EQUALS => toBooleanObject(leftInteger != rightInteger),
        .LESS_THAN => toBooleanObject(leftInteger < rightInteger),
        .GREATER_THAN => toBooleanObject(leftInteger > rightInteger),
    };

    return result;
}

fn evaluateFunction(self: *@This(), function: ast.Function, env: *Environment) !*Object {
    const functionObject = try createObject(self.allocator);

    const value = try self.allocator.create(object.Function);

    value.body = function.body;
    value.parameters = function.parameters;
    value.env = env;

    functionObject.value = Value{ .function = value };
    return functionObject;
}

fn evaluateIdentifier(self: *@This(), identifier: ast.Identifier, env: *Environment) !*Object {
    if (try env.get(identifier.name)) |value| return value;

    if (self.builtins.get(identifier.name)) |builtin| return @constCast(builtin);

    return try createErrorObject(
        identifier.token.line,
        identifier.token.column,
        "identifier not found: {s}",
        .{identifier.name},
        self.allocator,
    );
}

const LEN_ARGS = 1;

fn len(self: *@This(), args: []*Object, token: Token) Allocator.Error!*Object {
    if (args.len != LEN_ARGS) return createErrorObject(
        token.line,
        token.column,
        "function call provided {} arguments instead of {}",
        .{ args.len, LEN_ARGS },
        self.allocator,
    );

    const obj = args[0];

    return switch (obj.value) {
        .string => |string| createIntegerObject(@intCast(string.len), self.allocator),
        .array => |array| createIntegerObject(@intCast(array.items.len), self.allocator),
        .@"error" => obj,
        else => try createErrorObject(
            token.line,
            token.column,
            "argument to 'len' not supported, got {s}",
            .{@tagName(obj.value)},
            self.allocator,
        ),
    };
}

const FIRST_ARGS = 1;

fn first(self: *@This(), args: []*Object, token: Token) Allocator.Error!*Object {
    if (args.len != FIRST_ARGS) return createErrorObject(
        token.line,
        token.column,
        "function call provided {} arguments instead of {}",
        .{ args.len, FIRST_ARGS },
        self.allocator,
    );

    const obj = args[0];

    switch (obj.value) {
        .array => |array| {
            if (array.items.len > 0) {
                array.items[0].inc();
                return array.items[0];
            } else {
                return @constCast(NULL);
            }
        },
        .@"error" => return obj,
        else => return try createErrorObject(
            token.line,
            token.column,
            "argument to 'first' not supported, got {s}",
            .{@tagName(obj.value)},
            self.allocator,
        ),
    }
}

const REST_ARGS = 1;

fn rest(self: *@This(), args: []*Object, token: Token) Allocator.Error!*Object {
    if (args.len != REST_ARGS) return createErrorObject(
        token.line,
        token.column,
        "function call provided {} arguments instead of {}",
        .{ args.len, REST_ARGS },
        self.allocator,
    );

    const obj = args[0];

    switch (obj.value) {
        .array => |array| {
            if (array.items.len == 0) return try createArrayObject(
                &[_]*Object{},
                &self.gc,
            );

            const objects = try self.allocator.alloc(*Object, array.items.len - 1);
            errdefer self.allocator.free(objects);

            for (array.items[1..], 0..) |item, i| {
                objects[i] = item;
                item.inc();
            }

            return try createArrayObject(objects, &self.gc);
        },
        .@"error" => return obj,
        else => return try createErrorObject(
            token.line,
            token.column,
            "argument to 'rest' not supported, got {s}",
            .{@tagName(obj.value)},
            self.allocator,
        ),
    }
}

const PUSH_ARGS = 2;

fn push(self: *@This(), args: []*Object, token: Token) Allocator.Error!*Object {
    if (args.len != PUSH_ARGS) return createErrorObject(
        token.line,
        token.column,
        "function call provided {} arguments instead of {}",
        .{ args.len, PUSH_ARGS },
        self.allocator,
    );

    const obj = args[0];

    switch (obj.value) {
        .array => |array| {
            if (args[1].value == .@"error") return args[1];
            try array.append(self.allocator, args[1]);
            args[1].inc();
            obj.inc();
            return obj;
        },
        .@"error" => {
            obj.inc();
            return obj;
        },
        else => return try createErrorObject(
            token.line,
            token.column,
            "argument to 'push' not supported, got {s}",
            .{@tagName(obj.value)},
            self.allocator,
        ),
    }
}

fn evaluateTestCase(self: *@This(), input: []const u8) !*Object {
    var scanner: Scanner = .init(input);

    var arena: ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    var parser: Parser = .init(arena.allocator(), &scanner);

    const program = try parser.parseProgram();

    return try self.evaluateProgram(program);
}

fn expectObject(self: *@This(), expected: *const Object, case: []const u8) !void {
    const result = try self.evaluateTestCase(case);
    defer result.dec(&self.gc);
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

    var evaluator = Evaluator.init(std.testing.allocator);
    defer evaluator.deinit();

    for (cases) |case| {
        const result = try evaluator.evaluateTestCase(case.@"test");

        try std.testing.expect(result.value == .integer);

        switch (result.value) {
            .integer => |integer| try std.testing.expectEqual(case.expect, integer),
            else => unreachable,
        }

        result.dec(&evaluator.gc);
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

    var evaluator = Evaluator.init(std.testing.allocator);
    defer evaluator.deinit();

    for (cases) |case| {
        const result = try evaluator.evaluateTestCase(case.@"test");

        try std.testing.expect(result.value == .boolean);

        std.testing.expectEqual(case.expect, result) catch |err| {
            std.debug.print("{s}\n", .{case.@"test"});
            std.debug.print("{} != {}\n", .{ case.expect.*, result.* });
            return err;
        };

        result.dec(&evaluator.gc);
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

    var evaluator = Evaluator.init(std.testing.allocator);
    defer evaluator.deinit();

    for (cases) |case| {
        const result = try evaluator.evaluateTestCase(case.@"test");

        try std.testing.expectEqual(case.expect, result.value);

        result.dec(&evaluator.gc);
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

    var evaluator = Evaluator.init(std.testing.allocator);
    defer evaluator.deinit();

    for (cases) |case| {
        const result = try evaluator.evaluateTestCase(case.@"test");

        try std.testing.expectEqualDeep(case.expect, result.value);

        result.dec(&evaluator.gc);
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

    var evaluator = Evaluator.init(std.testing.allocator);
    defer evaluator.deinit();

    for (cases) |case| {
        const result = try evaluator.evaluateTestCase(case.@"test");

        switch (result.value) {
            .@"error" => |@"error"| try std.testing.expectEqualSlices(u8, case.expect, @"error".message),
            else => try std.testing.expect(false),
        }

        result.dec(&evaluator.gc);
    }
}

test "test let statements" {
    const cases = [_]struct { @"test": []const u8, expect: i64 }{
        .{ .@"test" = "let a = 5; a;", .expect = 5 },
        .{ .@"test" = "let a = 5 * 5; a;", .expect = 25 },
        .{ .@"test" = "let a = 5; let b = a; b;", .expect = 5 },
        .{ .@"test" = "let a = 5; let a = 10; a;", .expect = 10 },
    };

    var evaluator = Evaluator.init(std.testing.allocator);
    defer evaluator.deinit();

    for (cases) |case| {
        const result = try evaluator.evaluateTestCase(case.@"test");

        switch (result.value) {
            .integer => |integer| try std.testing.expectEqual(case.expect, integer),
            else => try std.testing.expect(false),
        }

        result.dec(&evaluator.gc);
    }
}

test "test function literals" {
    var scanner: Scanner = .init("fn (x) { x + 2 }");

    var arena: ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    var parser: Parser = .init(arena.allocator(), &scanner);

    const program = try parser.parseProgram();

    var evaluator = Evaluator.init(std.testing.allocator);
    defer evaluator.deinit();

    const result = try evaluator.evaluateProgram(program);

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
        .env = &evaluator.root,
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

    result.dec(&evaluator.gc);
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

    var evaluator = Evaluator.init(std.testing.allocator);
    defer evaluator.deinit();

    for (cases) |case| {
        const result = try evaluator.evaluateTestCase(case.@"test");

        switch (result.value) {
            .integer => |integer| try std.testing.expectEqual(case.expect, integer),
            else => try std.testing.expect(false),
        }

        result.dec(&evaluator.gc);
    }
}

test "string evaluation" {
    var evaluator = Evaluator.init(std.testing.allocator);
    defer evaluator.deinit();

    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .string = "OLEN PARAS" } },
        \\"OLEN PARAS"
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .string = "MITÄ HONGYUAN TARVITSEE?" } },
        \\"MITÄ" + " " + "HONGYUAN" + " " + "TARVITSEE?"
    );
}

test "builtin len function" {
    var evaluator = Evaluator.init(std.testing.allocator);
    defer evaluator.deinit();

    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .integer = 0 } },
        \\len("");
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .integer = 4 } },
        \\len("four");
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .integer = 11 } },
        \\len("hello world");
    );
    try evaluator.expectObject(&Object{
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
    try evaluator.expectObject(&Object{
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

test "array evaluation" {
    var evaluator = Evaluator.init(std.testing.allocator);
    defer evaluator.deinit();

    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .integer = 1 } },
        \\[1, 2, 3][0];
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .integer = 2 } },
        \\[1, 2, 3][1];
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .integer = 3 } },
        \\[1, 2, 3][2];
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .string = "hello" } },
        \\["hello", "world"][0];
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .boolean = true } },
        \\[true, false][0];
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .boolean = false } },
        \\[true, false][1];
    );
    try evaluator.expectObject(&Object{
        .refs = 1,
        .value = .{
            .@"error" = @constCast(&object.Error{
                .column = 10,
                .line = 1,
                .message = "access out of bounds",
            }),
        },
    },
        \\[1, 2, 3][4];
    );
    try evaluator.expectObject(&Object{
        .refs = 1,
        .value = .{
            .@"error" = @constCast(&object.Error{
                .column = 3,
                .line = 1,
                .message = "access out of bounds",
            }),
        },
    },
        \\[][0];
    );
    try evaluator.expectObject(&Object{
        .refs = 1,
        .value = .{
            .@"error" = @constCast(&object.Error{
                .column = 4,
                .line = 1,
                .message = "array index must integer, not string",
            }),
        },
    },
        \\[1]["hello"];
    );
    try evaluator.expectObject(&Object{
        .refs = 1,
        .value = .{
            .@"error" = @constCast(&object.Error{
                .column = 2,
                .line = 1,
                .message = "integer object is not indexable",
            }),
        },
    },
        \\1[0];
    );
}

test "cyclic references" {
    var evaluator = Evaluator.init(std.testing.allocator);
    defer evaluator.deinit();

    {
        const result = try evaluator.evaluateTestCase(
            \\let arr = [];
            \\push(arr,arr);
        );
        result.dec(&evaluator.gc);
    }

    {
        const result = try evaluator.evaluateTestCase(
            \\let arr1 = [];
            \\let arr2 = [];
            \\push(arr1,arr2);
            \\push(arr2,arr1);
        );
        result.dec(&evaluator.gc);
    }
}

test "array builtin functions" {
    var evaluator = Evaluator.init(std.testing.allocator);
    defer evaluator.deinit();

    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .integer = 3 } },
        \\len([1, 2, 3]);
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .integer = 0 } },
        \\len([]);
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .integer = 1 } },
        \\first([1, 2, 3]);
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .string = "hello" } },
        \\first(["hello"]);
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .null = {} } },
        \\first([]);
    );
    try evaluator.expectObject(&Object{
        .refs = 1,
        .value = .{
            .@"error" = @constCast(&object.Error{
                .column = 6,
                .line = 1,
                .message = "argument to 'first' not supported, got integer",
            }),
        },
    },
        \\first(1);
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .integer = 2 } },
        \\len(rest([1, 2, 3]));
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .integer = 2 } },
        \\rest([1, 2, 3])[0];
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .integer = 0 } },
        \\len(rest([1]));
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .integer = 0 } },
        \\len(rest([]));
    );
    try evaluator.expectObject(&Object{
        .refs = 1,
        .value = .{
            .@"error" = @constCast(&object.Error{
                .column = 5,
                .line = 1,
                .message = "argument to 'rest' not supported, got integer",
            }),
        },
    },
        \\rest(1);
    );
    try evaluator.expectObject(&Object{ .refs = 2, .value = .{ .integer = 2 } },
        \\let a = [1];
        \\push(a, 2);
        \\a[1];
    );
    try evaluator.expectObject(&Object{ .refs = 1, .value = .{ .integer = 2 } },
        \\let a = [1];
        \\push(a, 2);
        \\len(a);
    );
    try evaluator.expectObject(&Object{ .refs = 2, .value = .{ .integer = 1 } },
        \\let a = [1];
        \\push(a, 2);
        \\a[0];
    );
    try evaluator.expectObject(&Object{
        .refs = 1,
        .value = .{
            .@"error" = @constCast(&object.Error{
                .column = 5,
                .line = 1,
                .message = "argument to 'push' not supported, got integer",
            }),
        },
    },
        \\push(1, 2);
    );
}
