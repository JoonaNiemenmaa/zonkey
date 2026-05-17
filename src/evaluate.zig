const std = @import("std");
const monkey = @import("root.zig");

const ast = monkey.ast;
const object = monkey.object;

const Object = object.Object;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const Environment = object.Environment;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const TRUE = Object{ .boolean = object.Boolean{ .value = true } };

pub const FALSE = Object{ .boolean = object.Boolean{ .value = false } };

pub const NULL = Object{ .null = object.Null{} };

const GCEntry = struct {
    object: *Object,
    marked: bool,
};

pub const Evaluator = struct {
    gpa: Allocator,
    objects: ArrayList(*Object),

    pub fn init(gpa: Allocator) @This() {
        return @This(){
            .gpa = gpa,
            .objects = ArrayList(*Object).empty,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.objects.deinit(self.gpa);
    }

    pub fn createObject(self: *@This()) !*Object {
        const obj = try self.gpa.create(Object);
        try self.objects.append(self.gpa, obj);
        return obj;
    }

    fn mark(self: *@This(), marked: *AutoHashMap(*Object, void), env: *Environment) !void {
        var iterator = env.bindings.iterator();
        var obj = iterator.next();
        while (obj != null) {
            const ptr = obj.?.value_ptr.*;

            switch (ptr.*) {
                .boolean => {},
                .null => {},
                else => try marked.put(ptr, {}),
            }

            obj = iterator.next();
        }
        if (env.outer) |outer| try self.mark(marked, outer);
    }

    pub fn collectGarbage(self: *@This(), env: *Environment, exclude: ?*Object) !void {
        var marked: AutoHashMap(*Object, void) = .init(self.gpa);
        defer marked.deinit();

        if (exclude) |excl| try marked.put(excl, {});

        try self.mark(&marked, env);

        var remove: ArrayList(usize) = .empty;
        defer remove.deinit(self.gpa);

        for (self.objects.items, 0..) |obj, i| {
            if (marked.contains(obj)) continue;
            self.destroyObject(obj);
            try remove.append(self.gpa, i);
        }

        const removeSlice = try remove.toOwnedSlice(self.gpa);
        defer self.gpa.free(removeSlice);

        self.objects.orderedRemoveMany(removeSlice);
    }

    pub fn destroyObject(self: *@This(), obj: *Object) void {
        switch (obj.*) {
            .integer => self.gpa.destroy(obj),
            .@"error" => |@"error"| {
                self.gpa.free(@"error".message);
                self.gpa.destroy(obj);
            },
            .function => {
                self.gpa.destroy(obj);
            },
            .@"return" => {
                self.gpa.destroy(obj);
            },
            else => {},
        }
    }

    fn newError(self: *@This(), line: usize, column: usize, comptime format: []const u8, args: anytype) !*Object {
        const @"error" = try self.createObject();
        @"error".* = Object{
            .@"error" = object.Error{
                .line = line,
                .column = column,
                .message = try std.fmt.allocPrint(self.gpa, format, args),
            },
        };
        return @"error";
    }

    fn toBooleanObject(boolean: bool) *Object {
        return @constCast(if (boolean) &TRUE else &FALSE);
    }

    fn createIntegerObject(self: *@This(), value: i64) !*Object {
        const integer = try self.createObject();
        integer.* = Object{
            .integer = object.Integer{
                .value = value,
            },
        };
        return integer;
    }

    pub fn evaluateProgram(self: *@This(), program: ast.Program, env: *Environment) !*Object {
        var result: *Object = @constCast(&NULL);
        for (program.statements) |statement| {
            result = try self.evaluateStatement(statement, env);

            try self.collectGarbage(env, result);

            switch (result.*) {
                .@"return" => |@"return"| return @"return".value,
                .@"error" => return result,
                else => {},
            }
        }
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
        var result: *Object = @constCast(&NULL);
        for (block.statements) |statement| {
            result = try self.evaluateStatement(statement, env);

            try self.collectGarbage(env, result);

            if (result.* == .@"return" or result.* == .@"error") return result;
        }
        return result;
    }

    fn evaluateReturn(self: *@This(), statement: ast.ReturnStatement, env: *Environment) !*Object {
        const result = try self.createObject();
        result.* = Object{ .@"return" = object.Return{ .value = try self.evaluateExpression(statement.expression.*, env) } };
        return result;
    }

    fn evaluateLet(self: *@This(), statement: ast.LetStatement, env: *Environment) !*Object {
        const result = try self.evaluateExpression(statement.expression.*, env);
        if (result.* == .@"error") return result;
        try env.put(statement.identifier.name, result);
        return result;
    }

    fn evaluateExpression(self: *@This(), expression: ast.Expression, env: *Environment) Allocator.Error!*Object {
        return switch (expression) {
            .identifier => |identifier| self.evaluateIdentifier(identifier, env),
            .integer => |integer| self.evaluateInteger(integer),
            .boolean => |boolean| evaluateBoolean(boolean),
            .prefix => |prefix| try self.evaluatePrefix(prefix, env),
            .infix => |infix| try self.evaluateInfix(infix, env),
            .@"if" => |@"if"| try self.evaluateIf(@"if", env),
            .function => |function| try self.evaluateFunction(function, env),
            .call => |call| try self.evaluateCall(call, env),
        };
    }

    fn evaluateCall(self: *@This(), call: ast.Call, env: *Environment) !*Object {
        const expression = try self.evaluateExpression(call.function.*, env);

        const function: object.Function = switch (expression.*) {
            .function => |function| function,
            .@"error" => return expression,
            else => |obj| return self.newError(call.token.line, call.token.column, "cannot call {s}", .{
                @tagName(obj),
            }),
        };

        if (function.parameters.len != call.arguments.len) return self.newError(
            call.token.line,
            call.token.column,
            "function call provided {} arguments instead of {}",
            .{ call.arguments.len, function.parameters.len },
        );

        const arguments = try self.evaluateArguments(call.arguments, env);
        defer self.gpa.free(arguments);

        var innerEnv: Environment = .init(self.gpa, function.env);

        for (function.parameters, arguments) |parameter, argument| {
            if (argument.* == .@"error") {
                innerEnv.bindings.clearAndFree();
                try self.collectGarbage(&innerEnv, null);
                innerEnv.deinit();
                return argument;
            }
            try innerEnv.put(parameter.name, argument);
        }

        const result = try self.evaluateBlock(function.body, &innerEnv);

        innerEnv.bindings.clearAndFree();
        try self.collectGarbage(&innerEnv, result);
        innerEnv.deinit();

        return switch (result.*) {
            .@"return" => |@"return"| @"return".value,
            else => result,
        };
    }

    fn evaluateArguments(self: *@This(), arguments: []*const ast.Expression, env: *Environment) ![]*Object {
        var evaluatedArguments: ArrayList(*Object) = .empty;
        errdefer evaluatedArguments.deinit(self.gpa);

        for (arguments) |argument| {
            const evaluated = try self.evaluateExpression(argument.*, env);
            try evaluatedArguments.append(self.gpa, evaluated);
        }

        return try evaluatedArguments.toOwnedSlice(self.gpa);
    }

    fn evaluateIf(self: *@This(), @"if": ast.If, env: *Environment) !*Object {
        const condition = try self.evaluateExpression(@constCast(@"if".condition).*, env);

        if (condition.* == .@"error") return condition;

        if (condition != &NULL and condition != &FALSE) {
            return try self.evaluateBlock(@"if".consequence, env);
        } else {
            return if (@"if".alternative) |alternative| try self.evaluateBlock(alternative, env) else @constCast(&NULL);
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
        return switch (operand.*) {
            .boolean => |boolean| toBooleanObject(!boolean.value),
            .null => toBooleanObject(true),
            .integer => |integer| toBooleanObject(integer.value == 0),
            else => self.newError(token.line, token.column, "unknown operator: {s}{s}", .{ token.literal, @tagName(operand.*) }),
        };
    }

    fn evaluatePrefixMinus(self: *@This(), token: monkey.token.Token, operand: *Object) !*Object {
        return switch (operand.*) {
            .integer => |integer| integerBlock: {
                operand.integer.value = -integer.value;
                break :integerBlock operand;
            },
            else => self.newError(token.line, token.column, "unknown operator: {s}{s}", .{ token.literal, @tagName(operand.*) }),
        };
    }

    fn evaluateInfix(self: *@This(), infix: ast.Infix, env: *Environment) !*Object {
        const left = try self.evaluateExpression(@constCast(infix.left).*, env);
        if (left.* == .@"error") return left;

        const right = try self.evaluateExpression(@constCast(infix.right).*, env);
        if (right.* == .@"error") return right;

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

    fn evaluateIntegerInfix(self: *@This(), left: *Object, operator: ast.InfixOperator, right: *Object) !*Object {
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

    fn evaluateFunction(self: *@This(), function: ast.Function, env: *Environment) !*Object {
        const functionObject = try self.createObject();
        functionObject.* = Object{
            .function = object.Function{
                .body = function.body,
                .parameters = function.parameters,
                .env = env,
            },
        };
        return functionObject;
    }

    fn evaluateIdentifier(self: *@This(), identifier: ast.Identifier, env: *Environment) !*Object {
        return if (try env.get(identifier.name)) |value| value else try self.newError(
            identifier.token.line,
            identifier.token.column,
            "identifier not found: {s}",
            .{identifier.name},
        );
    }

    fn evaluateInteger(self: *@This(), integer: ast.Integer) !*Object {
        const integerObject = try self.createObject();
        integerObject.* = Object{ .integer = object.Integer{ .value = integer.value } };
        return integerObject;
    }

    fn evaluateBoolean(boolean: ast.Boolean) *Object {
        return @constCast(if (boolean.value) &TRUE else &FALSE);
    }
};
