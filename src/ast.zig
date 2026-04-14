const std = @import("std");
const Token = @import("scanner.zig").Token;
const Writer = std.Io.Writer;
const ArenaAllocator = std.heap.ArenaAllocator;
const DebugAllocator = std.heap.DebugAllocator;
const Allocator = std.mem.Allocator;

pub const Program = struct {
    statements: []Statement,

    pub fn printProgram(self: @This(), writer: *Writer) !void {
        var gpa: DebugAllocator(.{}) = .init;
        var arena: ArenaAllocator = .init(gpa.allocator());
  
        defer arena.deinit();
        errdefer arena.deinit();
    
        const allocator = arena.allocator();

        for (self.statements) |statement| {
            try writer.print("{s};\n", .{ try statement.string(allocator) });
        }
    }
};

pub const Statement = union(enum) {
    letStatement: LetStatement,
    returnStatement: ReturnStatement,
    expressionStatement: ExpressionStatement,

    pub fn string(self: @This(), allocator: Allocator) ![]const u8 {
        return switch (self) {
            inline else => |s| try s.string(allocator),
        };
    }
};

pub const Expression = union(enum) {
    identifier: Identifier,
    integer: Integer,

    pub fn string(self: @This(), allocator: Allocator) ![]const u8 {
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
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE,
    EQUALS,
    NOT_EQUALS,
};

pub const Identifier = struct {
    token: Token,
    name: []const u8,

    pub fn string(self: @This(), allocator: Allocator) ![]const u8 {
        _ = allocator;
        return self.token.literal;
    }
};

pub const Integer = struct {
    token: Token,
    value: i64,

    pub fn string(self: @This(), allocator: Allocator) ![]const u8 {
        _ = allocator;
        return self.token.literal;
    }
};

pub const Prefix = struct {
    token: Token,
    operator: PrefixOperator,
    operand: *Expression,
};

pub const Infix = struct {
    token: Token,
    operator: InfixOperator,
    left_operand: *Expression,
    right_operand: *Expression,
};

pub const LetStatement = struct {
    token: Token,
    identifier: Identifier,
    expression: Expression,

    pub fn string(self: @This(), allocator: Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{s} {s} = {s}", .{
            self.token.literal,
            self.identifier.name,
            try self.expression.string(allocator),
        });
    }
};

pub const ReturnStatement = struct {
    token: Token,
    expression: Expression,

    pub fn string(self: @This(), allocator: Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{s} {s}", .{
            self.token.literal,
            try self.expression.string(allocator),
        });
    }
};

pub const ExpressionStatement = struct {
    token: Token,
    expression: Expression,

    pub fn string(self: @This(), allocator: Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{s}", .{
            try self.expression.string(allocator),
        });
    }
};

