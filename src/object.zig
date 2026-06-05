const std = @import("std");
const monkey = @import("root.zig");

const ast = monkey.ast;

const Writer = std.Io.Writer;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;
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
        try self.stack.append(self.gpa, ptr);
        return ptr;
    }

    pub fn createError(self: *@This(), line: usize, column: usize, comptime format: []const u8, args: anytype) !*Object {
        const @"error" = try self.createObject();
        @"error".* = Object{
            .@"error" = Error{
                .line = line,
                .column = column,
                .message = try std.fmt.allocPrint(self.gpa, format, args),
            },
        };
        return @"error";
    }

    fn mark(self: *@This(), marked: *AutoHashMap(*Object, void)) !void {
        var iterator = self.bindings.iterator();
        var entry = iterator.next();
        while (entry != null) {
            const ptr = entry.?.value_ptr.*;

            switch (ptr.*) {
                .boolean => {},
                .null => {},
                else => try marked.put(ptr, {}),
            }

            entry = iterator.next();
        }

        if (self.outer) |outer| try outer.mark(marked);
    }

    pub fn markAndSweep(self: *@This(), exclude: ?*Object) !void {
        var marked: AutoHashMap(*Object, void) = .init(self.gpa);
        defer marked.deinit();

        if (exclude) |excl| try marked.put(excl, {});

        var iterator = self.bindings.valueIterator();
        while (iterator.next()) |entry| {
            const ptr = entry.*;
            switch (ptr.*) {
                .boolean => {},
                .null => {},
                else => try marked.put(ptr, {}),
            }
        }

        var remove: ArrayList(usize) = .empty;
        defer remove.deinit(self.gpa);

        for (self.stack.items, 0..) |ptr, i| {
            if (marked.contains(ptr)) continue;
            self.destroyObject(ptr);
            try remove.append(self.gpa, i);
        }

        const removeSlice = try remove.toOwnedSlice(self.gpa);
        defer self.gpa.free(removeSlice);

        self.stack.orderedRemoveMany(removeSlice);
    }

    pub fn destroyObject(self: *@This(), ptr: *Object) void {
        switch (ptr.*) {
            .integer => self.gpa.destroy(ptr),
            .@"error" => |@"error"| {
                self.gpa.free(@"error".message);
                self.gpa.destroy(ptr);
            },
            .function => {
                self.gpa.destroy(ptr);
            },
            .@"return" => {
                self.gpa.destroy(ptr);
            },
            else => {},
        }
    }

    pub fn deinit(self: *@This(), exclude: ?*Object) void {
        self.bindings.clearAndFree();
        self.markAndSweep(exclude) catch {};
        self.stack.deinit(self.gpa);
        self.bindings.deinit();
    }
};
