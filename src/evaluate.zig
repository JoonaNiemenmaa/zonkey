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

pub const TRUE = &Object{
    .mark = false,
    .value = Value{ .boolean = true },
};

pub const FALSE = &Object{
    .mark = false,
    .value = Value{ .boolean = false },
};

pub const NULL = &Object{
    .mark = false,
    .value = Value{ .null = {} },
};

fn toBooleanObject(boolean: bool) *Object {
    return @constCast(if (boolean) TRUE else FALSE);
}

fn createStringObject(value: []const u8, env: *Environment) !*Object {
    const stringObject = try env.createObject();
    const string = try env.gpa.alloc(u8, value.len);
    std.mem.copyForwards(u8, string, value);
    stringObject.value = Value{ .string = string };
    return stringObject;
}

fn createIntegerObject(value: i64, env: *Environment) !*Object {
    const integer = try env.createObject();
    integer.value = Value{ .integer = value };
    return integer;
}

pub fn createErrorObject(line: usize, column: usize, comptime format: []const u8, args: anytype, env: *Environment) !*Object {
    const @"error" = try env.createObject();

    const value = try env.gpa.create(object.Error);

    value.line = line;
    value.column = column;
    value.message = try std.fmt.allocPrint(env.gpa, format, args);

    @"error".value = Value{ .@"error" = value };
    return @"error";
}

pub fn evaluateProgram(program: ast.Program, env: *Environment) !*Object {
    var result: *Object = @constCast(NULL);
    for (program.statements) |statement| {
        result = try evaluateStatement(statement, env);

        try env.markAndSweep(result);

        switch (result.value) {
            .@"return" => |value| return value,
            .@"error" => return result,
            else => {},
        }
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
    for (block.statements) |statement| {
        result = try evaluateStatement(statement, env);
        try env.markAndSweep(result);
        if (result.value == .@"return" or result.value == .@"error") return result;
    }
    try env.markAndSweep(result);
    return result;
}

fn evaluateReturn(statement: ast.ReturnStatement, env: *Environment) !*Object {
    const result = try env.createObject();
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
        .integer => |integer| evaluateInteger(integer, env),
        .boolean => |boolean| toBooleanObject(boolean.value),
        .string => |string| evaluateString(string, env),
        .prefix => |prefix| try evaluatePrefix(prefix, env),
        .infix => |infix| try evaluateInfix(infix, env),
        .@"if" => |@"if"| try evaluateIf(@"if", env),
        .function => |function| try evaluateFunction(function, env),
        .call => |call| try evaluateCall(call, env),
    };
}

fn evaluateCall(call: ast.Call, env: *Environment) !*Object {
    const expression = try evaluateExpression(call.function.*, env);

    const function = switch (expression.value) {
        .function => |function| function,
        .@"error" => return expression,
        else => |value| return createErrorObject(call.token.line, call.token.column, "cannot call {s}", .{
            @tagName(value),
        }, env),
    };

    if (function.parameters.len != call.arguments.len) return createErrorObject(
        call.token.line,
        call.token.column,
        "function call provided {} arguments instead of {}",
        .{ call.arguments.len, function.parameters.len },
        env,
    );

    const arguments = try evaluateArguments(call.arguments, env);
    defer env.gpa.free(arguments);

    var innerEnv: Environment = .init(env.gpa, function.env);

    for (function.parameters, arguments) |parameter, argument| {
        if (argument.value == .@"error") {
            innerEnv.deinit(null);
            return argument;
        }
        try innerEnv.put(parameter.name, argument);
    }

    const result = try evaluateBlock(function.body, &innerEnv);

    const returnObject = switch (result.value) {
        .@"return" => |@"return"| @"return",
        else => result,
    };

    defer innerEnv.deinit(returnObject);

    if (std.mem.find(*Object, arguments, &[_]*Object{returnObject}) == null) try env.stack.append(env.gpa, returnObject);

    return returnObject;
}

fn evaluateArguments(arguments: []*const ast.Expression, env: *Environment) ![]*Object {
    var evaluatedArguments: ArrayList(*Object) = .empty;
    errdefer evaluatedArguments.deinit(env.gpa);

    for (arguments) |argument| {
        const evaluated = try evaluateExpression(argument.*, env);
        try evaluatedArguments.append(env.gpa, evaluated);
    }

    return try evaluatedArguments.toOwnedSlice(env.gpa);
}

fn evaluateIf(@"if": ast.If, env: *Environment) !*Object {
    const condition = try evaluateExpression(@constCast(@"if".condition).*, env);

    if (condition.value == .@"error") return condition;

    if (condition != NULL and condition != FALSE) {
        return try evaluateBlock(@"if".consequence, env);
    } else {
        return if (@"if".alternative) |alternative| try evaluateBlock(alternative, env) else @constCast(NULL);
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
            env,
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
            env,
        ),
    };
}

fn evaluateInfix(infix: ast.Infix, env: *Environment) !*Object {
    const left = try evaluateExpression(@constCast(infix.left).*, env);
    if (left.value == .@"error") return left;

    const right = try evaluateExpression(@constCast(infix.right).*, env);
    if (right.value == .@"error") return right;

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
                env,
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
        env,
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
            const result = try env.createObject();

            result.value = Value{
                .string = try std.mem.concat(env.gpa, u8, &.{ leftString, rightString }),
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
            env,
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
        .ADD => try createIntegerObject(leftInteger + rightInteger, env),
        .SUBTRACT => try createIntegerObject(leftInteger - rightInteger, env),
        .MULTIPLY => try createIntegerObject(leftInteger * rightInteger, env),
        .DIVIDE => try createIntegerObject(@divFloor(leftInteger, rightInteger), env),

        .EQUALS => toBooleanObject(leftInteger == rightInteger),
        .NOT_EQUALS => toBooleanObject(leftInteger != rightInteger),
        .LESS_THAN => toBooleanObject(leftInteger < rightInteger),
        .GREATER_THAN => toBooleanObject(leftInteger > rightInteger),
    };

    return result;
}

fn evaluateFunction(function: ast.Function, env: *Environment) !*Object {
    const functionObject = try env.createObject();

    const value = try env.gpa.create(object.Function);

    value.body = function.body;
    value.parameters = function.parameters;
    value.env = env;

    functionObject.value = Value{ .function = value };
    return functionObject;
}

fn evaluateIdentifier(identifier: ast.Identifier, env: *Environment) !*Object {
    return if (try env.get(identifier.name)) |value| value else try createErrorObject(
        identifier.token.line,
        identifier.token.column,
        "identifier not found: {s}",
        .{identifier.name},
        env,
    );
}

fn evaluateInteger(integer: ast.Integer, env: *Environment) !*Object {
    const integerObject = try env.createObject();
    integerObject.value = Value{ .integer = integer.value };
    return integerObject;
}

fn evaluateString(string: ast.String, env: *Environment) !*Object {
    const stringObject = try env.createObject();
    const value = try env.gpa.alloc(u8, string.value.len);
    std.mem.copyForwards(u8, value, string.value);
    stringObject.value = Value{ .string = value };
    return stringObject;
}
