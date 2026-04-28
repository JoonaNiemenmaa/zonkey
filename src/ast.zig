const std = @import("std");
const monkey = @import("root.zig");

const Writer = std.Io.Writer;
const ArrayList = std.ArrayList;
const ArenaAllocator = std.heap.ArenaAllocator;
const DebugAllocator = std.heap.DebugAllocator;
const Allocator = std.mem.Allocator;

const Token = monkey.token.Token;

pub const Program = struct {
    statements: []Statement,

    pub fn printProgram(self: @This(), writer: *Writer) !void {
        var gpa: DebugAllocator(.{}) = .init;
        var arena: ArenaAllocator = .init(gpa.allocator());

        defer arena.deinit();

        const allocator = arena.allocator();

        try writer.flush();
        for (self.statements) |statement| {
            try writer.print("{s}\n", .{try statement.string(allocator)});
        }
    }
};

pub const Statement = union(enum) {
    letStatement: LetStatement,
    returnStatement: ReturnStatement,
    expressionStatement: ExpressionStatement,
    blockStatement: Block,

    pub fn string(self: @This(), allocator: Allocator) Allocator.Error![]const u8 {
        return switch (self) {
            inline else => |s| try s.string(allocator),
        };
    }
};

pub const Expression = union(enum) {
    identifier: Identifier,
    integer: Integer,
    boolean: Boolean,
    prefix: Prefix,
    infix: Infix,
    @"if": If,
    function: Function,

    pub fn string(self: @This(), allocator: Allocator) Allocator.Error![]const u8 {
        return switch (self) {
            inline else => |e| try e.string(allocator),
        };
    }
};

pub const PrefixOperator = enum {
    NOT,
    MINUS,
};

pub const InfixOperator = enum {
    EQUALS,
    NOT_EQUALS,
    LESS_THAN,
    GREATER_THAN,
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE,
};

pub const Boolean = struct {
    token: Token,
    value: bool,

    pub fn string(self: @This(), allocator: Allocator) Allocator.Error![]const u8 {
        _ = allocator;
        return self.token.literal;
    }
};

pub const Identifier = struct {
    token: Token,
    name: []const u8,

    pub fn string(self: @This(), allocator: Allocator) Allocator.Error![]const u8 {
        _ = allocator;
        return self.token.literal;
    }
};

pub const Integer = struct {
    token: Token,
    value: i64,

    pub fn string(self: @This(), allocator: Allocator) Allocator.Error![]const u8 {
        _ = allocator;
        return self.token.literal;
    }
};

pub const Function = struct {
    token: Token,
    arguments: []const Identifier,
    body: Block,

    pub fn string(self: @This(), allocator: Allocator) Allocator.Error![]const u8 {

        var args: ArrayList(u8) = .empty;
        errdefer args.deinit(allocator);

        for (self.arguments, 0..) |argument, index| {
            try args.appendSlice(allocator, argument.name);
            if (index < self.arguments.len - 1) {
                try args.appendSlice(allocator, ", ");
            }
        }

        return try std.fmt.allocPrint(allocator, "fn ({s}) {s}", .{
            try args.toOwnedSlice(allocator),
            try self.body.string(allocator)
        });
    }
};

pub const Prefix = struct {
    token: Token,
    operator: PrefixOperator,
    operand: *const Expression,

    pub fn string(self: @This(), allocator: Allocator) Allocator.Error![]const u8 {
        return try std.fmt.allocPrint(allocator, "({s}{s})", .{
            self.token.literal,
            try self.operand.string(allocator),
        });
    }
};

pub const Infix = struct {
    token: Token,
    operator: InfixOperator,
    left: *const Expression,
    right: *const Expression,

    pub fn string(self: @This(), allocator: Allocator) Allocator.Error![]const u8 {
        return try std.fmt.allocPrint(allocator, "({s} {s} {s})", .{
            try self.left.string(allocator),
            self.token.literal,
            try self.right.string(allocator),
        });
    }
};

pub const If = struct {
    token: Token,
    condition: *const Expression,
    consequence: Block,
    alternative: ?Block,

    pub fn string(self: @This(), allocator: Allocator) Allocator.Error![]const u8 {
        return try std.fmt.allocPrint(allocator, "if ({s}) {s}{s}{s}", .{
            try self.condition.string(allocator),
            try self.consequence.string(allocator),
            if (self.alternative != null) " else " else "",
            if (self.alternative) |a| try a.string(allocator) else "",
        });
    }
};

pub const Block = struct {
    token: Token,
    statements: []const Statement,

    pub fn string(self: @This(), allocator: Allocator) Allocator.Error![]const u8 {
        var block: ArrayList(u8) = .empty;
        errdefer block.deinit(allocator);

        try block.appendSlice(allocator, "{\n");

        for (self.statements) |statement| {
            try block.print(allocator, "    {s}\n", .{try statement.string(allocator)});
        }

        try block.appendSlice(allocator, "}");

        return try block.toOwnedSlice(allocator);
    }
};

pub const LetStatement = struct {
    token: Token,
    identifier: Identifier,
    expression: *const Expression,

    pub fn string(self: @This(), allocator: Allocator) Allocator.Error![]const u8 {
        return try std.fmt.allocPrint(allocator, "{s} {s} = {s};", .{
            self.token.literal,
            self.identifier.name,
            try self.expression.string(allocator),
        });
    }
};

pub const ReturnStatement = struct {
    token: Token,
    expression: *const Expression,

    pub fn string(self: @This(), allocator: Allocator) Allocator.Error![]const u8 {
        return try std.fmt.allocPrint(allocator, "{s} {s};", .{
            self.token.literal,
            try self.expression.string(allocator),
        });
    }
};

pub const ExpressionStatement = struct {
    token: Token,
    expression: *const Expression,

    pub fn string(self: @This(), allocator: Allocator) Allocator.Error![]const u8 {
        return try std.fmt.allocPrint(allocator, "{s}", .{
            try self.expression.string(allocator),
        });
    }
};
