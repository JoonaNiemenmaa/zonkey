const std = @import("std");
const monkey = @import("root.zig");

const ast = monkey.ast;

const Writer = std.Io.Writer;
const StringHashMap = std.StringHashMap;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const ObjectType = enum {
    integer,
    boolean,
    null,
    @"return",
    @"error",
    function,
};

pub const Object = union(ObjectType) {
    integer: Integer,
    boolean: Boolean,
    null: Null,
    @"return": Return,
    @"error": Error,
    function: Function,

    pub fn print(self: @This(), writer: *Writer) !void {
        switch (self) {
            .integer => |integer| try writer.print("{}\n", .{integer.value}),
            .boolean => |boolean| try writer.print("{}\n", .{boolean.value}),
            .null => try writer.print("null\n", .{}),
            .@"return" => |@"return"| try @"return".value.print(writer),
            .@"error" => |@"error"| try writer.print("{}:{} {s}\n", .{ @"error".line, @"error".column, @"error".message }),
            .function => |function| {
                try writer.print("fn (", .{});
                for (function.parameters, 0..) |parameter, i| {
                    try parameter.print(writer);
                    if (i < function.parameters.len - 1) try writer.print(", ", .{});
                }
                try writer.print(") ", .{});
                try function.body.print(writer);
                try writer.print("\n", .{});
            },
        }
    }
};

pub const Error = struct {
    line: usize,
    column: usize,
    message: []const u8,
};

pub const Return = struct {
    value: *Object,
};

pub const Integer = struct {
    value: i64,
};

pub const Boolean = struct {
    value: bool,
};

pub const Null = struct {};

pub const Function = struct {
    parameters: []const ast.Identifier,
    body: ast.Block,
    env: *Environment,
};

pub const Environment = struct {
    bindings: StringHashMap(*Object),
    arena: Allocator,

    pub fn init(arena: Allocator) @This() {
        return @This(){
            .bindings = StringHashMap(*Object).init(arena), .arena = arena,
        };
    }

    pub fn put(self: *@This(), key: []const u8, obj: *Object) !void {
        switch (obj.*) {
            .integer => {
                const value = try self.arena.create(Object);
                value.* = obj.*;
                try self.bindings.put(key, value);
            },
            else => {
                try self.bindings.put(key, obj);
            },
        }
    }

    pub fn get(self: *@This(), allocator: Allocator, key: []const u8) !?*Object {
        if (self.bindings.get(key)) |value| {
            switch (value.*) {
                .integer => {
                    const integer = try allocator.create(Object);
                    integer.* = value.*;
                    return integer;
                },
                else => {
                    return value;
                },
            }
        } else {
            return null;
        }
    }

    pub fn deinit(self: *@This()) void {
        self.bindings.deinit();
    }
};

