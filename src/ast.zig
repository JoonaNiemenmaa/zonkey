const std = @import("std");
const monkey = @import("root.zig");

const TokenType = monkey.token.TokenType;
const Writer = std.Io.Writer;
const ArrayList = std.ArrayList;
const ArenaAllocator = std.heap.ArenaAllocator;
const DebugAllocator = std.heap.DebugAllocator;
const Allocator = std.mem.Allocator;

const Token = monkey.token.Token;

pub const Node = union(enum) {
    program: Program,
    statement: Statement,
    expression: Expression,
};

pub const Program = struct {
    statements: []Statement,

    pub fn printProgram(self: @This(), writer: *Writer) !void {
        for (self.statements) |statement| {
            try statement.print(writer);
        }
    }
};

pub const Statement = union(enum) {
    letStatement: LetStatement,
    returnStatement: ReturnStatement,
    expressionStatement: ExpressionStatement,
    blockStatement: Block,

    pub fn print(self: @This(), writer: *Writer) Writer.Error!void {
        return switch (self) {
            inline else => |statement| {
                try statement.print(writer);
                try writer.print(";\n", .{});
            },
        };
    }
};

pub const LetStatement = struct {
    token: Token,
    identifier: Identifier,
    expression: *const Expression,

    pub fn print(self: @This(), writer: *Writer) !void {
        try writer.print("let ", .{});
        try self.identifier.print(writer);
        try writer.print(" = ", .{});
        try self.expression.print(writer);
    }
};

pub const ReturnStatement = struct {
    token: Token,
    expression: *const Expression,

    pub fn print(self: @This(), writer: *Writer) !void {
        try writer.print("return ", .{});
        try self.expression.print(writer);
    }
};

pub const ExpressionStatement = struct {
    token: Token,
    expression: *const Expression,

    pub fn print(self: @This(), writer: *Writer) !void {
        try self.expression.print(writer);
    }
};

pub const Block = struct {
    
    token: Token,
    statements: []const Statement,

    pub fn print(self: @This(), writer: *Writer) !void {
        try writer.print("{{\n", .{});
        for (self.statements) |statement| {
            try writer.print("    ", .{});
            try statement.print(writer);
        }
        try writer.print("}}", .{});
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
    call: Call,

    pub fn print(self: @This(), writer: *Writer) Writer.Error!void {
        return switch (self) {
            inline else => |expression| try expression.print(writer),
        };
    }
};

pub const Boolean = struct {
    token: Token,
    value: bool,

    pub fn print(self: @This(), writer: *Writer) !void {
        try writer.print("{}", .{self.value});
    }
};

pub const Identifier = struct {
    token: Token,
    name: []const u8,

    pub fn print(self: @This(), writer: *Writer) !void {
        try writer.print("{s}", .{self.name});
    }
};

pub const Integer = struct {
    token: Token,
    value: i64,

    pub fn print(self: @This(), writer: *Writer) !void {
        try writer.print("{}", .{self.value});
    }
};

pub const Function = struct {
    token: Token,
    parameters: []const Identifier,
    body: Block,

    pub fn print(self: @This(), writer: *Writer) !void {
        try writer.print("fn (", .{});for (self.parameters, 0..) |identifier, i| {
            try identifier.print(writer);
            if (i < self.parameters.len - 1) try writer.print(", ", .{});
        }
        try writer.print(") ", .{});
        try self.body.print(writer);
    }
};

pub const Call = struct {
    token: Token,
    function: *const Expression,
    arguments: []*const Expression,

    pub fn print(self: @This(), writer: *Writer) !void {
        try self.function.print(writer);
    }
};

pub const PrefixOperator = enum {
    NOT,
    MINUS,
};

pub fn getPrefixOperator(@"type": TokenType) PrefixOperator {
    return switch (@"type") {
        .BANG => .NOT,
        .MINUS => .MINUS,
        else => unreachable,
    };
}

pub const Prefix = struct {
    token: Token,
    operator: PrefixOperator,
    operand: *const Expression,

    pub fn print(self: @This(), writer: *Writer) !void {
        try writer.print("{s}(", .{self.token.literal});
        try self.operand.print(writer);
        try writer.print(")", .{});
    }
};

pub const InfixOperator = enum {
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE,
    EQUALS,
    NOT_EQUALS,
    LESS_THAN,
    GREATER_THAN,
};

pub fn getInfixOperator(@"type": TokenType) InfixOperator {
    return switch (@"type") {
        .PLUS => .ADD,
        .MINUS => .SUBTRACT,
        .ASTERISK => .MULTIPLY,
        .SLASH => .DIVIDE,
        .EQUALS => .EQUALS,
        .NOT_EQUALS => .NOT_EQUALS,
        .LESS_THAN => .LESS_THAN,
        .GREATER_THAN => .GREATER_THAN,
        else => unreachable,
    };
}

pub const Infix = struct {
    token: Token,
    operator: InfixOperator,
    left: *const Expression,
    right: *const Expression,

    pub fn print(self: @This(), writer: *Writer) !void {
        try writer.print("(", .{});
        try self.left.print(writer);
        try writer.print(" {s} ", .{self.token.literal});
        try self.right.print(writer);
        try writer.print(")", .{});
    }
};

pub const If = struct {
    token: Token,
    condition: *const Expression,
    consequence: Block,
    alternative: ?Block,

    pub fn print(self: @This(), writer: *Writer) !void {
        try writer.print("if (", .{});
        try self.condition.print(writer);
        try writer.print(") ", .{});
        try self.consequence.print(writer);
        if (self.alternative) |alternative| {
            try writer.print(" else ", .{});
            try alternative.print(writer);
        }
    }
};
