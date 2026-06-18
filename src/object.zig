const std = @import("std");
const monkey = @import("root.zig");

const ast = monkey.ast;

const Writer = std.Io.Writer;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const Object = struct {
    mark: bool,
    value: Value,

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
    stack: ArrayList(*Object),
    gpa: Allocator,
    outer: ?*Environment,

    pub fn init(allocator: Allocator, outer: ?*Environment) @This() {
        return @This(){
            .bindings = StringHashMap(*Object).init(allocator),
            .stack = ArrayList(*Object).empty,
            .outer = outer,
            .gpa = allocator,
        };
    }

    pub fn put(self: *@This(), key: []const u8, obj: *Object) !void {
        try self.bindings.put(key, obj);
    }

    pub fn get(self: *@This(), key: []const u8) !?*Object {
        if (self.bindings.get(key)) |value| {
            return value;
        } else {
            if (self.outer) |outer| return try outer.get(key) else return null;
        }
    }

    pub fn createObject(self: *@This()) !*Object {
        const ptr = try self.gpa.create(Object);
        ptr.mark = false;
        try self.stack.append(self.gpa, ptr);
        return ptr;
    }

    pub fn markAndSweep(self: *@This(), exclude: ?*Object) !void {
        if (exclude) |e| e.mark = true;

        var iterator = self.bindings.valueIterator();
        while (iterator.next()) |entry| {
            const ptr = entry.*;
            switch (ptr.value) {
                .boolean => {},
                .null => {},
                else => ptr.mark = true,
            }
        }

        var remove: ArrayList(usize) = .empty;
        defer remove.deinit(self.gpa);

        for (self.stack.items, 0..) |ptr, i| {
            if (!ptr.mark) {
                self.destroyObject(ptr);
                try remove.append(self.gpa, i);
            } else {
                ptr.mark = false;
            }
        }

        const removeSlice = try remove.toOwnedSlice(self.gpa);
        defer self.gpa.free(removeSlice);

        self.stack.orderedRemoveMany(removeSlice);
    }

    pub fn destroyObject(self: *@This(), ptr: *Object) void {
        if (ptr.value == .null or ptr.value == .boolean) return;
        switch (ptr.value) {
            .integer => {},
            .@"return" => {},
            .string => |string| self.gpa.free(string),
            .@"error" => |@"error"| {
                self.gpa.free(@"error".message);
                self.gpa.destroy(@"error");
            },
            .function => |function| self.gpa.destroy(function),
            else => unreachable,
        }
        self.gpa.destroy(ptr);
    }

    pub fn deinit(self: *@This(), exclude: ?*Object) void {
        self.bindings.clearAndFree();
        self.markAndSweep(exclude) catch {};
        self.stack.deinit(self.gpa);
        self.bindings.deinit();
    }
};
