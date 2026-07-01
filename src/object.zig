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
const DoublyLinkedList = std.DoublyLinkedList;

const Token = monkey.token.Token;
const Evaluator = monkey.evaluate.Evaluator;

pub const TRUE = &Object{ .value = Value{ .boolean = true } };
pub const FALSE = &Object{ .value = Value{ .boolean = false } };
pub const NULL = &Object{ .value = Value{ .null = {} } };

pub fn toBooleanObject(boolean: bool) *Object {
    return @constCast(if (boolean) TRUE else FALSE);
}

pub fn createObject(allocator: Allocator) !*Object {
    const ptr = try allocator.create(Object);
    ptr.* = .{ .value = Value{ .null = {} } };
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

pub fn createArrayObject(objects: []*Object, gc: *GarbageCollector) !*Object {
    var array = try gc.allocator.create(ArrayList(*Object));
    errdefer gc.allocator.destroy(array);

    array.* = .fromOwnedSlice(objects);
    errdefer array.deinit(gc.allocator);

    const object = try createObject(gc.allocator);

    object.value = Value{ .array = array };

    gc.containers.append(&object.node);

    return object;
}

pub fn createEnvObject(outer: ?*Environment, gc: *GarbageCollector) !*Environment {
    const object = try createObject(gc.allocator);
    errdefer gc.allocator.destroy(object);

    const env = try gc.allocator.create(Environment);
    errdefer gc.allocator.destroy(env);

    env.* = .init(gc.allocator, outer, object);

    object.* = .{ .value = .{ .env = env } };

    gc.containers.append(&object.node);

    return env;
}

pub const Object = struct {
    value: Value,

    refs: usize = 1,
    gcRefs: usize = 1,
    reachable: bool = true,
    node: DoublyLinkedList.Node = .{},

    pub fn inc(self: *@This()) void {
        self.refs += 1;
    }

    pub fn dec(self: *@This(), gc: *GarbageCollector) void {
        if (self.refs > 0) self.refs -= 1;
        if (self.refs == 0) {
            switch (self.value) {
                .null => return,
                .boolean => return,
                .builtin => return,
                .integer => {},
                .@"return" => {},
                .string => |string| gc.allocator.free(string),
                .@"error" => |@"error"| {
                    gc.allocator.free(@"error".message);
                    gc.allocator.destroy(@"error");
                },
                .function => |function| {
                    gc.containers.remove(&self.node);
                    function.env.object.dec(gc);
                    gc.allocator.destroy(function);
                },
                .array => |array| {
                    gc.containers.remove(&self.node);
                    for (array.items) |item| item.dec(gc);
                    array.deinit(gc.allocator);
                    gc.allocator.destroy(array);
                },
                .env => |env| {
                    gc.containers.remove(&self.node);
                    env.deinit(gc);
                    gc.allocator.destroy(env);
                },
            }
            gc.allocator.destroy(self);
        }
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
            .env => |env| try writer.print("ENV: {}\n", .{env}),
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
    builtin: *const fn (*Evaluator, []*Object, Token) Allocator.Error!*Object,
    array: *ArrayList(*Object),
    env: *Environment,
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
    object: *Object,

    pub fn init(allocator: Allocator, outer: ?*Environment, object: *Object) @This() {
        return @This(){
            .bindings = .init(allocator),
            .outer = outer,
            .allocator = allocator,
            .object = object,
        };
    }

    pub fn put(self: *@This(), key: []const u8, obj: *Object, gc: *GarbageCollector) !void {
        if (self.bindings.get(key)) |value| {
            if (value != obj) {
                value.dec(gc);
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

    pub fn deinit(self: *@This(), gc: *GarbageCollector) void {
        var i = self.bindings.valueIterator();
        while (i.next()) |value| value.*.dec(gc);
        self.bindings.deinit();
    }
};

pub const GarbageCollector = struct {
    allocator: Allocator,
    containers: DoublyLinkedList = .{},

    pub fn init(allocator: Allocator) @This() {
        return @This(){ .allocator = allocator };
    }

    fn isContainer(object: *Object) bool {
        return object.value == .array or object.value == .function or object.value == .env;
    }

    pub fn collect(self: *@This()) void {
        //std.debug.print("-----------------------------\n", .{});
        {
            var i = self.containers.first;
            while (i) |node| : (i = node.next) {
                const container: *Object = @fieldParentPtr("node", node);
                container.gcRefs = container.refs;
                container.reachable = true;
            }
        }

        {
            var i = self.containers.first;
            while (i) |node| : (i = node.next) {
                const container: *Object = @fieldParentPtr("node", node);
                switch (container.value) {
                    .array => |array| for (array.items) |object| {
                        if (isContainer(object)) object.gcRefs -= 1;
                    },
                    .function => |function| {
                        function.env.object.gcRefs -= 1;
                    },
                    .env => |env| {
                        var bindingIterator = env.bindings.valueIterator();
                        while (bindingIterator.next()) |ptr| {
                            const value = ptr.*;
                            if (value.value == .function) value.gcRefs -= 1;
                        }
                    },
                    else => unreachable,
                }
            }
        }

        // {
        //     var i = self.containers.first;
        //     while (i) |node| : (i = node.next) {
        //         const container: *Object = @fieldParentPtr("node", node);
        //         std.debug.print("{}\n", .{container});
        //     }
        // }

        var @"unreachable": DoublyLinkedList = .{};
        {
            var i = self.containers.first;
            while (i) |node| {
                const container: *Object = @fieldParentPtr("node", node);
                i = node.next;
                if (container.gcRefs > 0) {
                    switch (container.value) {
                        .array => |array| for (array.items) |object| {
                            if (object.gcRefs == 0 and isContainer(object)) {
                                object.gcRefs = 1;
                                if (!object.reachable) {
                                    @"unreachable".remove(&object.node);
                                    self.containers.append(&object.node);
                                }
                            }
                        },
                        .function => |function| {
                            const object = function.env.object;
                            if (object.gcRefs == 0) {
                                object.gcRefs = 1;
                                if (!object.reachable) {
                                    @"unreachable".remove(&object.node);
                                    self.containers.append(&object.node);
                                }
                            }
                        },
                        .env => |env| {
                            var bindingIterator = env.bindings.valueIterator();
                            while (bindingIterator.next()) |ptr| {
                                const value = ptr.*;
                                if (value.gcRefs == 0 and value.value == .function) {
                                    value.gcRefs = 1;
                                    if (!value.reachable) {
                                        @"unreachable".remove(&value.node);
                                        self.containers.append(&value.node);
                                    }
                                }
                            }
                        },
                        else => unreachable,
                    }
                } else {
                    container.reachable = false;
                    self.containers.remove(&container.node);
                    @"unreachable".append(&container.node);
                }
            }
        }

        {
            var i = @"unreachable".first;
            while (i) |node| {
                const object: *Object = @fieldParentPtr("node", node);
                i = node.next;

                switch (object.value) {
                    .array => |array| {
                        for (array.items) |item| if (!isContainer(item)) item.dec(self);
                        array.deinit(self.allocator);
                        self.allocator.destroy(array);
                    },
                    .function => |function| {
                        self.allocator.destroy(function);
                    },
                    .env => |env| {
                        var envIterator = env.bindings.valueIterator();
                        while (envIterator.next()) |ptr| if (ptr.*.value != .function) ptr.*.dec(self);
                        env.bindings.deinit();
                        self.allocator.destroy(env);
                    },
                    else => unreachable,
                }
                self.allocator.destroy(object);
            }
        }
    }
};
