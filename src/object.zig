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
        .string => |string| createIntegerObject(@intCast(string.len), env.allocator),
        .array => |array| createIntegerObject(@intCast(array.items.len), env.allocator),
        .@"error" => obj,
        else => try createErrorObject(
            token.line,
            token.column,
            "argument to 'len' not supported, got {s}",
            .{@tagName(obj.value)},
            env.allocator,
        ),
    };
}

const FIRST_ARGS = 1;

fn first(args: []*Object, token: Token, env: *Environment) Allocator.Error!*Object {
    if (args.len != FIRST_ARGS) return createErrorObject(
        token.line,
        token.column,
        "function call provided {} arguments instead of {}",
        .{ args.len, FIRST_ARGS },
        env.allocator,
    );

    const obj = args[0];

    switch (obj.value) {
        .array => |array| {
            if (array.items.len > 0) {
                array.items[0].inc();
                return array.items[0];
            } else {
                return @constCast(NULL);
            }
        },
        .@"error" => return obj,
        else => return try createErrorObject(
            token.line,
            token.column,
            "argument to 'first' not supported, got {s}",
            .{@tagName(obj.value)},
            env.allocator,
        ),
    }
}

const REST_ARGS = 1;

fn rest(args: []*Object, token: Token, env: *Environment) Allocator.Error!*Object {
    if (args.len != REST_ARGS) return createErrorObject(
        token.line,
        token.column,
        "function call provided {} arguments instead of {}",
        .{ args.len, REST_ARGS },
        env.allocator,
    );

    const obj = args[0];

    switch (obj.value) {
        .array => |array| {
            if (array.items.len == 0) return try createArrayObject(
                &[_]*Object{},
                env.allocator,
            );

            const objects = try env.allocator.alloc(*Object, array.items.len - 1);
            errdefer env.allocator.free(objects);

            for (array.items[1..], 0..) |item, i| {
                objects[i] = item;
                item.inc();
            }

            return try createArrayObject(objects, env.allocator);
        },
        .@"error" => return obj,
        else => return try createErrorObject(
            token.line,
            token.column,
            "argument to 'rest' not supported, got {s}",
            .{@tagName(obj.value)},
            env.allocator,
        ),
    }
}

const PUSH_ARGS = 2;

fn push(args: []*Object, token: Token, env: *Environment) Allocator.Error!*Object {
    if (args.len != PUSH_ARGS) return createErrorObject(
        token.line,
        token.column,
        "function call provided {} arguments instead of {}",
        .{ args.len, PUSH_ARGS },
        env.allocator,
    );

    const obj = args[0];

    switch (obj.value) {
        .array => |array| {
            if (args[1].value == .@"error") return args[1];
            try array.append(env.allocator, args[1]);
            args[1].inc();
            obj.inc();
            return obj;
        },
        .@"error" => {
            obj.inc();
            return obj;
        },
        else => return try createErrorObject(
            token.line,
            token.column,
            "argument to 'push' not supported, got {s}",
            .{@tagName(obj.value)},
            env.allocator,
        ),
    }
}

pub const builtins: StaticStringMap(*const Object) = .initComptime(.{
    .{
        "len",
        &Object{
            .refs = 1,
            .value = .{ .builtin = &len },
        },
    },
    .{
        "first",
        &Object{
            .refs = 1,
            .value = .{ .builtin = &first },
        },
    },
    .{
        "rest",
        &Object{
            .refs = 1,
            .value = .{ .builtin = &rest },
        },
    },
    .{
        "push",
        &Object{
            .refs = 1,
            .value = .{ .builtin = &push },
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

pub fn createArrayObject(objects: []*Object, allocator: Allocator) !*Object {
    var array = try allocator.create(ArrayList(*Object));
    array.* = .fromOwnedSlice(objects);

    errdefer {
        array.deinit(allocator);
        allocator.destroy(array);
    }

    const object = try createObject(allocator);
    errdefer object.destroy(allocator);

    object.value = Value{ .array = array };

    return object;
}

pub const Object = struct {
    refs: usize,
    value: Value,

    pub fn inc(self: *@This()) void {
        self.refs += 1;
    }

    pub fn dec(self: *@This(), allocator: Allocator) void {
        if (self.refs > 0) self.refs -= 1;
        if (self.refs == 0) {
            switch (self.value) {
                .array => |array| for (array.items) |item| item.dec(allocator),
                else => {},
            }
            self.destroy(allocator);
        }
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
            .array => |array| {
                array.deinit(allocator);
                allocator.destroy(array);
            },
        }
        allocator.destroy(self);
    }

    pub fn print(self: @This(), writer: *Writer) !void {
        switch (self.value) {
            .boolean => |boolean| try writer.print("{}", .{boolean}),
            .null => try writer.print("null", .{}),
            .integer => |integer| try writer.print("{}", .{integer}),
            .string => |string| try writer.print("{s}", .{string}),
            .@"return" => |@"return"| try @"return".print(writer),
            .@"error" => |@"error"| try writer.print("ERROR: {}:{} {s}", .{
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
            },
            .builtin => |builtin| try writer.print("BUILTIN: {}\n", .{builtin}),
            .array => |array| {
                try writer.print("[", .{});
                for (array.items, 1..) |item, i| {
                    switch (item.value) {
                        .array => try writer.print("[...]", .{}),
                        else => try item.print(writer),
                    }
                    if (i < array.items.len) try writer.print(", ", .{});
                }
                try writer.print("]", .{});
            },
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
    array: *ArrayList(*Object),
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
