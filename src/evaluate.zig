const std = @import("std");
const monkey = @import("root.zig");

const ast = monkey.ast;
const object = monkey.object;

const Object = object.Object;
const ArrayList = std.ArrayList;
const Environment = object.Environment;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const TRUE = Object{ .boolean = object.Boolean{ .value = true } };
pub const FALSE = Object{ .boolean = object.Boolean{ .value = false } };
pub const NULL = Object{ .null = object.Null{} };

fn toBooleanObject(boolean: bool) *Object {
    return @constCast(if (boolean) &TRUE else &FALSE);
}

fn createIntegerObject(value: i64, env: *Environment) !*Object {
    const integer = try env.createObject();
    integer.* = Object{
        .integer = object.Integer{
            .value = value,
        },
    };
    return integer;
}

pub fn evaluateProgram(program: ast.Program, env: *Environment) !*Object {
    var result: *Object = @constCast(&NULL);
    for (program.statements) |statement| {
        result = try evaluateStatement(statement, env);

        try env.markAndSweep(result);

        switch (result.*) {
            .@"return" => |@"return"| return @"return".value,
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
    var result: *Object = @constCast(&NULL);
    for (block.statements) |statement| {
        result = try evaluateStatement(statement, env);
        if (result.* == .@"return" or result.* == .@"error") return result;
    }
    try env.markAndSweep(result);
    return result;
}

fn evaluateReturn(statement: ast.ReturnStatement, env: *Environment) !*Object {
    const result = try env.createObject();
    result.* = Object{ .@"return" = object.Return{ .value = try evaluateExpression(statement.expression.*, env) } };
    return result;
}

fn evaluateLet(statement: ast.LetStatement, env: *Environment) !*Object {
    const result = try evaluateExpression(statement.expression.*, env);
    if (result.* == .@"error") return result;
    try env.put(statement.identifier.name, result);
    return result;
}

fn evaluateExpression(expression: ast.Expression, env: *Environment) Allocator.Error!*Object {
    return switch (expression) {
        .identifier => |identifier| evaluateIdentifier(identifier, env),
        .integer => |integer| evaluateInteger(integer, env),
        .boolean => |boolean| evaluateBoolean(boolean),
        .prefix => |prefix| try evaluatePrefix(prefix, env),
        .infix => |infix| try evaluateInfix(infix, env),
        .@"if" => |@"if"| try evaluateIf(@"if", env),
        .function => |function| try evaluateFunction(function, env),
        .call => |call| try evaluateCall(call, env),
    };
}

fn evaluateCall(call: ast.Call, env: *Environment) !*Object {
    const expression = try evaluateExpression(call.function.*, env);

    const function: object.Function = switch (expression.*) {
        .function => |function| function,
        .@"error" => return expression,
        else => |obj| return env.createError(call.token.line, call.token.column, "cannot call {s}", .{
            @tagName(obj),
        }),
    };

    if (function.parameters.len != call.arguments.len) return env.createError(
        call.token.line,
        call.token.column,
        "function call provided {} arguments instead of {}",
        .{ call.arguments.len, function.parameters.len },
    );

    const arguments = try evaluateArguments(call.arguments, env);
    defer env.gpa.free(arguments);

    var innerEnv: Environment = .init(env.gpa, function.env);

    for (function.parameters, arguments) |parameter, argument| {
        if (argument.* == .@"error") {
            innerEnv.deinit(null);
            return argument;
        }
        try innerEnv.put(parameter.name, argument);
    }

    const result = try evaluateBlock(function.body, &innerEnv);

    const value = switch (result.*) {
        .@"return" => |@"return"| @"return".value,
        else => result,
    };

    defer innerEnv.deinit(value);

    if (std.mem.find(*Object, arguments, &[_]*Object{value}) == null) try env.stack.append(env.gpa, value);

    return value;
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

    if (condition.* == .@"error") return condition;

    if (condition != &NULL and condition != &FALSE) {
        return try evaluateBlock(@"if".consequence, env);
    } else {
        return if (@"if".alternative) |alternative| try evaluateBlock(alternative, env) else @constCast(&NULL);
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
    return switch (operand.*) {
        .boolean => |boolean| toBooleanObject(!boolean.value),
        .null => toBooleanObject(true),
        .integer => |integer| toBooleanObject(integer.value == 0),
        else => env.createError(token.line, token.column, "unknown operator: {s}{s}", .{ token.literal, @tagName(operand.*) }),
    };
}

fn evaluatePrefixMinus(token: monkey.token.Token, operand: *Object, env: *Environment) !*Object {
    return switch (operand.*) {
        .integer => |integer| integerBlock: {
            operand.integer.value = -integer.value;
            break :integerBlock operand;
        },
        else => env.createError(token.line, token.column, "unknown operator: {s}{s}", .{ token.literal, @tagName(operand.*) }),
    };
}

fn evaluateInfix(infix: ast.Infix, env: *Environment) !*Object {
    const left = try evaluateExpression(@constCast(infix.left).*, env);
    if (left.* == .@"error") return left;

    const right = try evaluateExpression(@constCast(infix.right).*, env);
    if (right.* == .@"error") return right;

    if (left.* == .integer and right.* == .integer) {
        return evaluateIntegerInfix(left, infix.operator, right, env);
    } else if (left.* == .boolean and right.* == .boolean) {
        return switch (infix.operator) {
            .EQUALS => toBooleanObject(left == right),
            .NOT_EQUALS => toBooleanObject(left != right),
            else => env.createError(infix.token.line, infix.token.column, "unknown operator: {s} {s} {s}", .{ @tagName(left.*), infix.token.literal, @tagName(right.*) }),
        };
    }

    return env.createError(infix.token.line, infix.token.column, "type mismatch: {s} {s} {s}", .{ @tagName(left.*), infix.token.literal, @tagName(right.*) });
}

fn evaluateIntegerInfix(left: *Object, operator: ast.InfixOperator, right: *Object, env: *Environment) !*Object {
    const leftInteger = switch (left.*) {
        .integer => |integer| integer,
        else => unreachable,
    };

    const rightInteger = switch (right.*) {
        .integer => |integer| integer,
        else => unreachable,
    };

    const result = switch (operator) {
        .ADD => try createIntegerObject(leftInteger.value + rightInteger.value, env),
        .SUBTRACT => try createIntegerObject(leftInteger.value - rightInteger.value, env),
        .MULTIPLY => try createIntegerObject(leftInteger.value * rightInteger.value, env),
        .DIVIDE => try createIntegerObject(@divFloor(leftInteger.value, rightInteger.value), env),

        .EQUALS => toBooleanObject(leftInteger.value == rightInteger.value),
        .NOT_EQUALS => toBooleanObject(leftInteger.value != rightInteger.value),
        .LESS_THAN => toBooleanObject(leftInteger.value < rightInteger.value),
        .GREATER_THAN => toBooleanObject(leftInteger.value > rightInteger.value),
    };

    return result;
}

fn evaluateFunction(function: ast.Function, env: *Environment) !*Object {
    const functionObject = try env.createObject();
    functionObject.* = Object{
        .function = object.Function{
            .body = function.body,
            .parameters = function.parameters,
            .env = env,
        },
    };
    return functionObject;
}

fn evaluateIdentifier(identifier: ast.Identifier, env: *Environment) !*Object {
    return if (try env.get(identifier.name)) |value| value else try env.createError(
        identifier.token.line,
        identifier.token.column,
        "identifier not found: {s}",
        .{identifier.name},
    );
}

fn evaluateInteger(integer: ast.Integer, env: *Environment) !*Object {
    const integerObject = try env.createObject();
    integerObject.* = Object{ .integer = object.Integer{ .value = integer.value } };
    return integerObject;
}

fn evaluateBoolean(boolean: ast.Boolean) *Object {
    return @constCast(if (boolean.value) &TRUE else &FALSE);
}
