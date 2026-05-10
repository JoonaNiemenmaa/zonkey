const std = @import("std");
const monkey = @import("root.zig");

const ast = monkey.ast;
const object = monkey.object;

const Object = object.Object;
const Environment = object.Environment;
const Allocator = std.mem.Allocator;

pub const TRUE = Object{ .boolean = object.Boolean{ .value = true } };

pub const FALSE = Object{ .boolean = object.Boolean{ .value = false } };

pub const NULL = Object{ .null = object.Null{} };

pub const Evaluator = struct {
    gpa: Allocator,

    pub fn init(gpa: Allocator) @This() {
        return @This(){
            .gpa = gpa,
        };
    }

    pub fn destroyObject(self: @This(), obj: *Object) void {
        switch (obj.*) {
            .integer => self.gpa.destroy(obj),
            .@"error" => |@"error"| {
                self.gpa.free(@"error".message);
                self.gpa.destroy(obj);
            },
            .@"return" => |@"return"| {
                self.destroyObject(@"return".value);
                self.gpa.destroy(obj);
            },
            else => {},
        }
    }

    fn newErr,r(self: @This(), line: usize, column: usize, comptime format: []const u8, args: anytype) !*Object {
        const @"error" = try self.gpa.create(Object);
        @"error".* = Object{
            .@"error" = object.Error{
                .line = line,
                .column = column,
                .message = try std.fmt.allocPrint(self.gpa, format, args),
            },
        };
        return @"error";
    }

    fn getNull() *Object {
        return @constCast(&NULL);
    }

    fn toBooleanObject(boolean: bool) *Object {
        return @constCast(if (boolean) &TRUE else &FALSE);
    }

    fn createIntegerObject(self: @This(), value: i64) !*Object {
        const integer = try self.gpa.create(Object);
        integer.* = Object{ .integer = object.Integer{
            .value = value,
        } };
        return integer;
    }

    pub fn evaluateProgram(self: @This(), program: ast.Program, env: *Environment) !*Object {
        var result: *Object = @constCast(&NULL);
        for (program.statements, 0..) |statement, i| {
            result = try self.evaluateStatement(statement, env);

            switch (result.*) {
                .@"return" => |@"return"| {
                    defer s,elf.gpa.destroy(result);
                    return @"return".value;
                },
                .@"error" => return result,
                else => if (i < program.statements.len - 1) self.destroyObject(result),
            }
        }
        return result;
    }

    fn evaluateStatement(self: @This(), statement: ast.Statement, env: *Environment) Allocator.Error!*Object {
        return switch (statement) {
            .expressionStatement => |expressionStatement| try self.evaluateExpression(expressionStatement.expression.*, env),
            .returnStatement => |returnStatement| try self.evaluateReturn(returnStatement, env),
            .letStatement => |letStatement| try self.evaluateLet(letStatement, env),
            //.blockStatement => |block| try self.evaluateBlock(block, env),
            else => unreachable,
        };
    }

    fn evaluateBlock(self: @This(), block: ast.Block, env: *Environment) !*Object {
        var result: *Object = @constCast(&NULL);
        for (block.statements, 0..) |statement, i| {
            result = try self.evaluateStatement(statement, env);

            if (result.* ==, .@"return" or result.* == .@"error") return result;

            if (i < block.statements.len - 1) self.destroyObject(result);
        }
        return result;
    }

    fn evaluateReturn(self: @This(), statement: ast.ReturnStatement, env: *Environment) !*Object {
        const result = try self.gpa.create(Object);
        result.* = Object{ .@"return" = object.Return{ .value = try self.evaluateExpression(statement.expression.*, env) } };
        return result;
    }

    fn evaluateLet(self: @This(), statement: ast.LetStatement, env: *Environment) !*Object {
        const result = try self.evaluateExpression(statement.expression.*, env);
        if (result.* == .@"error") return result;
        try env.put(statement.identifier.name, result);
        return result;
    }

    fn evaluateExpression(self: @This(), expression: ast.Expression, env: *Environment) Allocator.Error!*Object {
        return switch (expression) {
            .identifier => |identifier| self.evaluateIdentifier(identifier, env),
            .integer => |integer| self.evaluateInteger(integer),
            .boolean => |boolean| evaluateBoolean(boolean),
            .prefix => |prefix| try self.evaluatePrefix(prefix, env),
            .infix => |infix| try self.evaluateInfix(infix, env),
            .@"if" => |@"if"| try self.evaluateIf(@"if", env),
            else => unreachable,
        };
    }

    fn evaluateIf(self: @This(), @"if": ast.If, env: *Environment) !*Object {
        const condition = try self.evaluateExpression(@constCast(@"if".condition).*, env);

        if (condition.* == .@"error") return condition;

        defer self.destroyObject(condition);

        if (condition != &NULL and condition != &FALSE) {
        } else {
            return if (@"if".alternative) |alternative| try self.evaluateBlock(alternative, env) else getNull();
        }
    }

    fn evaluatePrefix(self: @This(), prefix: ast.Prefix, env: *Environment) !*Object {
        const operand = try self.evaluateExpression(prefix.operand.*, env);

        return switch (prefix.operator) {
            .NOT => self.evaluatePrefixBang(prefix.token, operand),
            .MINUS => self.evaluatePrefixMinus(prefix.token, operan
    fn evaluatePrefixBang(self: @This(), token: monkey.token.Token, operand: *Object) !*Object {
        defer self.destroyObject(operand);
        return switch (operand.*) {
            .boolean => |boolean| toBooleanObject(!boolean.value),
            .null => toBooleanObject(true),
            .integer => |integer| toBooleanObject(integer.value == 0),
            else => self.newError(token.line, token.column, "unknown operator: {s}{s}", .{ token.literal, @tagName(operand.*) }),
        };
    }

    fn evaluatePrefixMinus(self: @This(), token: monkey.token.Token, operand: *Object) !*Object {
        return switch (operand.*) {
            .integer => |integer| integerBlock: {
                operand.integer.value = -integer.value;
                break :integerBlock operand;
            },
            else => self.newError(token.line, token.column, "unknown operator: {s}{s}", .{ token.literal, @tagName(operand.*) }),
        };
    }

    fn evaluateInfix(self: @This(), infix: ast.Infix, env: *Environment) !*Object {
        const left = try self.evaluateExpression(@constCast(infix.left).*, env);
        const right = try self.evaluateExpression(@constCast(infix.right).*, env);

        defer {
            self.destroyObject(left);
            self.destroyObject(right);
        }

        if (left.* == .integer and right.* == .integer) {
            return self.evaluateIntegerInfix(left, infix.operator, right);
        } else if (left.* == .boolean and right.* == .boolean) {
            return switch (infix.operator) {
                .EQUALS => toBooleanObject(left == right),
                .NOT_EQUALS => toBooleanObject(left != right),
                else => self.newError(infix.token.line, infix.token.column, "unknown operator: {s} {s} {s}", .{ @tagName(left.*), infix.token.literal, @tagName(right.*) }),
            };
        }

        return self.newError(infix.token.line, infix.token.column, "type mismatch: {s} {s} {s}", .{ @tagName(left.*), infix.token.literal, @tagName(right.*) });
    }

    fn evaluateIntegerInfix(self: @This(), left: *Object, operator: ast.InfixOperator, right: *Object) !*Object {
        const leftInteger = switch (left.*) {
            .integer => |integer| integer,
            else => unreachable,
        };

        const rightInteger = switch (right.*) {
            .integer => |integer| integer,
            else => unreachable,
        };

        const result = switch (operator) {
            .ADD => try self.createIntegerObject(leftInteger.value + rightInteger.value),
            .SUBTRACT => try self.createIntegerObject(leftInteger.value - rightInteger.value),
            .MULTIPLY => try self.createIntegerObject(leftInteger.value * rightInteger.value),
            .DIVIDE => try self.createIntegerObject(@divFloor(leftInteger.value, rightInteger.value)),

            .EQUALS => toBooleanObject(leftInteger.value == rightInteger.value),
            .NOT_EQUALS => toBooleanObject(leftInteger.value != rightInteger.value),
            .LESS_THAN => toBooleanObject(leftInteger.value < rightInteger.value),
            .GREATER_THAN => toBooleanObject(leftInteger.value > rightInteger.value),
        };

        return result;
    }

    fn evaluateIdentifier(self: @This(), identifier: ast.Identifier, env: *Environment) !*Object {
        return if (try env.get(self.gpa, identifier.name)) |value| value else try self.newError(identifier.token.line, identifier.token.column, "identifier not found: {s}", .{identifier.name});
    }

    fn evaluateInteger(self: @This(), integer: ast.Integer) !*Object {
        const integerObject = try self.gpa.create(Object);
        integerObject.* = Object{ .integer = object.Integer{ .value = integer.value } };
        return integerObject;
    }

    fn evaluateBoolean(boolean: ast.Boolean) *Object {
        return @constCast(if (boolean.value) &TRUE else &FALSE);
    }
};
