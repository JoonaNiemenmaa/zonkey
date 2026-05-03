const std = @import("std");
const monkey = @import("root.zig");

const ast = monkey.ast;
const object = monkey.object;

const Object = object.Object;
const Allocator = std.mem.Allocator;

pub const Evaluator = struct{
    gpa: Allocator,

    TRUE: Object,
    FALSE: Object,
    NULL: Object,

    pub fn init(gpa: Allocator) @This() {
        return @This(){
            .gpa = gpa,
            .TRUE = Object{
                .boolean = object.Boolean{ .value = true }
            },
            .FALSE = Object{
                .boolean = object.Boolean{ .value = false }
            },
            .NULL = Object{
                .@"null" = object.Null{}
            }
        };
    }

    pub fn evaluateProgram(self: @This(), program: ast.Program) !?*Object {
        var result: ?*Object = null;
        for (program.statements) |statement| {
            result = try self.evaluateStatement(statement);
        }
        return result;
    }

    fn evaluateStatement(self: @This(), statement: ast.Statement) !*Object {
        return switch (statement) {
            .expressionStatement => |expressionStatement| try self.evaluateExpression(expressionStatement.expression.*),
            else => unreachable,
        };
    }

    fn evaluatePrefixBang(self: @This(), operand: *Object) !*Object {
        return switch (operand.*) {
            .boolean => |boolean| @constCast(if (boolean.value) &self.FALSE else &self.TRUE),
            .@"null" => |_| @constCast(&self.TRUE),
            .integer => |integer| integerBlock: {
                defer self.gpa.destroy(operand);
                break :integerBlock @constCast(if (integer.value != 0) &self.FALSE else &self.TRUE);
            },
        };
    }

    fn evaluatePrefixMinus(self: @This(), operand: *Object) !*Object {
        return switch (operand.*) {
            .integer => |integer| integerBlock: {
                operand.integer.value = -integer.value;
                break :integerBlock operand;
            },
            else => @constCast(&self.NULL),
        };
    }

    fn evaluatePrefix(self: @This(), prefix: ast.Prefix) !*Object {
        const operand = try self.evaluateExpression(prefix.operand.*);

        return switch (prefix.operator) {
            .NOT => self.evaluatePrefixBang(operand),
            .MINUS => self.evaluatePrefixMinus(operand),
        };
    }

    fn evaluateInfix(self: @This(), infix: ast.Infix) !*Object {

        const left = try self.evaluateExpression(@constCast(infix.left).*);
        const right = try self.evaluateExpression(@constCast(infix.right).*);

        const leftOperand: object.Integer = switch (left.*) {
            .integer => |integer| integer,
            else => {
                return @constCast(&self.NULL);
            }
        };

        const rightOperand: object.Integer = switch (right.*) {
            .integer => |integer| integer,
            else => {
                return @constCast(&self.NULL);
            }
        };

        defer self.gpa.destroy(right);

        switch (infix.operator) {
            .ADD => {
                left.* = Object{
                    .integer = object.Integer{
                        .value = leftOperand.value + rightOperand.value
                    }
                };
            },
            .SUBTRACT => {
                left.* = Object{
                    .integer = object.Integer{
                        .value = leftOperand.value - rightOperand.value
                    }
                };
            },
            .MULTIPLY => {
                left.* = Object{
                    .integer = object.Integer{
                        .value = leftOperand.value * rightOperand.value
                    }
                };
            },
            .DIVIDE => {
                left.* = Object{
                    .integer = object.Integer{
                        .value = @divFloor(leftOperand.value, rightOperand.value)
                    }
                };
            },
            .EQUALS => {
                left.* = Object{
                    .boolean = object.Boolean{
                        .value = leftOperand.value == rightOperand.value
                    }
                };
            },
            .NOT_EQUALS => {
                left.* = Object{
                    .boolean = object.Boolean{
                        .value = leftOperand.value != rightOperand.value
                    }
                };
            },
            .LESS_THAN => {
                left.* = Object{
                    .boolean = object.Boolean{
                        .value = leftOperand.value < rightOperand.value
                    }
                };
            },
            .GREATER_THAN => {
                left.* = Object{
                    .boolean = object.Boolean{
                        .value = leftOperand.value > rightOperand.value
                    }
                };
            },
        }

        return left;
    }

    fn evaluateInteger(self: @This(), integer: ast.Integer) !*Object {
        const integerObject = try self.gpa.create(Object);
        integerObject.* = Object{
            .integer = object.Integer{ .value = integer.value }
        };
        return integerObject;
    }

    fn evaluateBoolean(self: @This(), boolean: ast.Boolean) *Object {
        return @constCast(if (boolean.value) &self.TRUE else &self.FALSE);
    }

    fn evaluateExpression(self: @This(), expression: ast.Expression) Allocator.Error!*Object {
        return switch (expression) {
            .integer => |integer| self.evaluateInteger(integer),
            .boolean => |boolean| self.evaluateBoolean(boolean),
            .prefix => |prefix| try self.evaluatePrefix(prefix),
            .infix => |infix| try self.evaluateInfix(infix),
            else => unreachable,
        };
    }
};

