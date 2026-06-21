const std = @import("std");
const monkey = @import("root.zig");

const ast = monkey.ast;

const Writer = std.Io.Writer;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const StaticStringMap = std.StaticStringMap;
const Token = monkey.token.Token;

pub const TRUE = &Object{
    .refs = 1,
    .value = Value{ .boolean = true },
};

pub const FALSE = &Object{
    .refs = 1,
    .value = Value{ .boolean = false },
};

pub const NULL = &Object{
    .refs = 1,
    .value = Value{ .null = {} },
};

const LEN_ARGS = 1;

fn len(args: []*Object, token: Token, env: *Environment) Allocator.Error!*Object {
    if (args.len != LEN_ARGS) return createErrorObject(
        token.line,
        token.column,
        "function call provided {} arguments instead of {}",
        .{ args.len, LEN_ARGS },
        env.allocator,
    );

    const obj = args[0];

    return switch (obj.value) {
        .string => |string| return createIntegerObject(@intCast(string.len), env.allocator),
        else => try createErrorObject(
            token.line,
            token.column,
            "argument to 'len' not supported, got {s}",
            .{@tagName(obj.value)},
            env.allocator,
        ),
    };
}

pub const builtins: StaticStringMap(*const Object) = .initComptime(.{
    .{
        "len",
        &Object{
            .refs = 1,
            .value = .{ .builtin = &len },
        },
    },
});

pub fn toBooleanObject(boolean: bool) *Object {
    return @constCast(if (boolean) TRUE else FALSE);
}

pub fn createObject(allocator: Allocator) !*Object {
    const ptr = try allocator.create(Object);
    ptr.refs = 1;
    return ptr;
}

pub fn createStringObject(value: []const u8, allocator: Allocator) !*Object {
    const stringObject = try createObject(allocator);
    const string = try allocator.alloc(u8, value.len);
    std.mem.copyForwards(u8, string, value);
    stringObject.value = Value{ .string = string };
    return stringObject;
}

pub fn createIntegerObject(value: i64, allocator: Allocator) !*Object {
    const integer = try createObject(allocator);
    integer.value = Value{ .integer = value };
    return integer;
}

pub fn createErrorObject(
    line: usize,
    column: usize,
    comptime format: []const u8,
    args: anytype,
    allocator: Allocator,
) !*Object {
    const @"error" = try createObject(allocator);

    const value = try allocator.create(Error);

    value.line = line;
    value.column = column;
    value.message = try std.fmt.allocPrint(allocator, format, args);

    @"error".value = Value{ .@"error" = value };
    return @"error";
}

pub const Object = struct {
    refs: usize,
    value: Value,

    pub fn inc(self: *@This()) void {
        self.refs += 1;
    }

    pub fn dec(self: *@This(), allocator: Allocator) void {
        if (self.refs > 0) self.refs -= 1;
        if (self.refs == 0) self.destroy(allocator);
    }

    pub fn destroy(self: *@This(), allocator: Allocator) void {
        switch (self.value) {
            .null => return,
            .boolean => return,
            .builtin => return,
            .integer => {},
            .@"return" => {},
            .string => |string| allocator.free(string),
            .@"error" => |@"error"| {
                allocator.free(@"error".message);
                allocator.destroy(@"error");
            },
            .function => |function| allocator.destroy(function),
        }
        allocator.destroy(self);
    }

    pub fn print(self: @This(), writer: *Writer) !void {
        switch (self.value) {
            .boolean => |boolean| try writer.print("{}\n", .{boolean}),
            .null => try writer.print("null\n", .{}),
            .integer => |integer| try writer.print("{}\n", .{integer}),
            .string => |string| try writer.print("\"{s}\"\n", .{string}),
            .@"return" => |@"return"| try @"return".print(writer),
            .@"error" => |@"error"| try writer.print("{}:{} {s}\n", .{
                @"error".line,
                @"error".column,
                @"error".message,
            }),
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
            .builtin => |builtin| try writer.print("BUILTIN: {}\n", .{builtin}),
        }
    }
};

pub const Value = union(enum) {
    integer: i64,
    boolean: bool,
    string: []const u8,
    null: void,
    @"return": *Object,
    @"error": *Error,
    function: *Function,
    builtin: *const fn ([]*Object, Token, *Environment) Allocator.Error!*Object,
};

pub const Error = struct {
    line: usize,
    column: usize,
    message: []const u8,
};

pub const Function = struct {
    parameters: []const ast.Identifier,
    body: ast.Block,
    env: *Environment,
};

pub const Environment = struct {
    bindings: StringHashMap(*Object),
    allocator: Allocator,
    outer: ?*Environment,

    pub fn init(allocator: Allocator, outer: ?*Environment) @This() {
        return @This(){
            .bindings = .init(allocator),
            .outer = outer,
            .allocator = allocator,
        };
    }

    pub fn put(self: *@This(), key: []const u8, obj: *Object) !void {
        if (self.bindings.get(key)) |value| {
            if (value != obj) {
                value.dec(self.allocator);
            }
        }
        try self.bindings.put(key, obj);
        obj.inc();
    }

    pub fn get(self: *@This(), key: []const u8) !?*Object {
        if (self.bindings.get(key)) |value| {
            value.inc();
            return value;
        } else {
            if (self.outer) |outer| return try outer.get(key) else return null;
        }
    }

    pub fn deinit(self: *@This()) void {
        var i = self.bindings.valueIterator();
        while (i.next()) |value| value.*.dec(self.allocator);
        self.bindings.deinit();
    }
};
