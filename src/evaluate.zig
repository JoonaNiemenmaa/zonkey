const std = @import("std");
const monkey = @import("root.zig");

const ast = monkey.ast;
const object = monkey.object;

const Object = object.Object;
const Allocator = std.mem.Allocator;

const TRUE = Object{
    .boolean = object.Boolean{ .value = true }
};

const FALSE = Object{
    .boolean = object.Boolean{ .value = false }
};

const NULL = Object{
    .@"null" = object.Null{}
};

pub const Evaluator = struct{
    gpa: Allocator,

    pub fn init(gpa: Allocator) @This() {
        return @This(){
            .gpa = gpa,
        };
    }

    fn destroyObject(self: @This(), obj: *Object) void {
        switch (obj.*) {
            .integer => self.gpa.destroy(obj),
            else => {}
        }
    }

    fn getNull() *Object {
        return @constCast(&NULL);
    }

    fn toBooleanObject(boolean: bool) *Object {
        return @constCast(if (boolean) &TRUE else &FALSE);
    }

    fn createIntegerObject(self: @This(), value: i64) !*Object {
        const integer = try self.gpa.create(Object);
        integer.* = Object{
            .integer = object.Integer{
                .value = value,
            }
        };
        return integer;
    }

    pub fn evaluateProgram(self: @This(), program: ast.Program) !*Object {
        var result: *Object = @constCast(&NULL);
        for (program.statements, 0..) |statement, i| {
            result = try self.evaluateStatement(statement);

            switch (result.*) {
                .@"return" => |@"return"| {
                    defer self.gpa.destroy(result);
                    return @"return".value;
                },
                else => if (i < program.statements.len - 1) self.destroyObject(result)
            }
        }
        return result;
    }

    fn evaluateStatement(self: @This(), statement: ast.Statement) Allocator.Error!*Object {
        return switch (statement) {
            .expressionStatement => |expressionStatement| try self.evaluateExpression(expressionStatement.expression.*),
            .returnStatement => |returnStatement| try self.evaluateReturn(returnStatement),
            .blockStatement => |block| try self.evaluateBlock(block),
            else => unreachable,
        };
    }

    fn evaluateBlock(self: @This(), block: ast.Block) !*Object {
        var result: *Object = @constCast(&NULL);
        for (block.statements, 0..) |statement, i| {
            result = try self.evaluateStatement(statement);

            if (result.* == .@"return") return result;

            if (i < block.statements.len - 1) self.destroyObject(result);
        }
        return result;
    }

    fn evaluateReturn(self: @This(), statement: ast.ReturnStatement) !*Object {
        const result = try self.gpa.create(Object);
        result.* = Object{
            .@"return" = object.Return{
                .value = try self.evaluateExpression(statement.expression.*)
            }
        };
        return result;
    }

    fn evaluateExpression(self: @This(), expression: ast.Expression) Allocator.Error!*Object {
        return switch (expression) {
            .integer => |integer| self.evaluateInteger(integer),
            .boolean => |boolean| evaluateBoolean(boolean),
            .prefix => |prefix| try self.evaluatePrefix(prefix),
            .infix => |infix| try self.evaluateInfix(infix),
            .@"if" => |@"if"| try self.evaluateIf(@"if"),
            else => unreachable,
        };
    }

    fn evaluateIf(self: @This(), @"if": ast.If) !*Object {
        const condition = try self.evaluateExpression(@constCast(@"if".condition).*);

        defer self.destroyObject(condition);
        
        if (condition != &NULL and condition != &FALSE) {
            return self.evaluateBlock(@"if".consequence);                
        } else {
            return if (@"if".alternative) |alternative| try self.evaluateBlock(alternative) else getNull();
        }

    }

    fn evaluatePrefix(self: @This(), prefix: ast.Prefix) !*Object {
        const operand = try self.evaluateExpression(prefix.operand.*);

        return switch (prefix.operator) {
            .NOT => self.evaluatePrefixBang(operand),
            .MINUS => evaluatePrefixMinus(operand),
        };
    }

    fn evaluatePrefixBang(self: @This(), operand: *Object) !*Object {
        defer self.destroyObject(operand);
        return switch (operand.*) {
            .boolean => |boolean| @constCast(if (boolean.value) &FALSE else &TRUE),
            .@"null" => |_| @constCast(&TRUE),
            .integer => |integer| integerBlock: {
                break :integerBlock @constCast(if (integer.value != 0) &FALSE else &TRUE);
            },
            else => unreachable
        };
    }

    fn evaluatePrefixMinus(operand: *Object) !*Object {
        return switch (operand.*) {
            .integer => |integer| integerBlock: {
                operand.integer.value = -integer.value;
                break :integerBlock operand;
            },
            else => @constCast(&NULL),
        };
    }

    fn evaluateInfix(self: @This(), infix: ast.Infix) !*Object {

        const left = try self.evaluateExpression(@constCast(infix.left).*);
        const right = try self.evaluateExpression(@constCast(infix.right).*);

        defer {
            self.destroyObject(left);
            self.destroyObject(right);
        }

        if (left.* == .integer and right.* == .integer) {
            return self.evaluateIntegerInfix(left, infix.operator, right);
        } else {
            return switch (infix.operator) {
                .EQUALS => toBooleanObject(left == right),
                .NOT_EQUALS => toBooleanObject(left != right),
                else => getNull()
            };
        }
    }

    fn evaluateIntegerInfix(self: @This(), left: *Object, operator: ast.InfixOperator, right: *Object) !*Object {

        const leftInteger = switch (left.*) {
            .integer => |integer| integer,
            else => return getNull()
        };

        const rightInteger = switch (right.*) {
            .integer => |integer| integer,
            else => return getNull()
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

    fn evaluateInteger(self: @This(), integer: ast.Integer) !*Object {
        const integerObject = try self.gpa.create(Object);
        integerObject.* = Object{
            .integer = object.Integer{ .value = integer.value }
        };
        return integerObject;
    }

    fn evaluateBoolean(boolean: ast.Boolean) *Object {
        return @constCast(if (boolean.value) &TRUE else &FALSE);
    }
};

