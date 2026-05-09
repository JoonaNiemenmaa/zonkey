const std = @import("std");

const Writer = std.Io.Writer;
const StringHashMap = std.StringHashMap;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const ObjectType = enum{
    integer,
    boolean,
    @"null",
    @"return",
    @"error",
};

pub const Object = union(ObjectType){
    integer: Integer,
    boolean: Boolean,
    @"null": Null,
    @"return": Return,
    @"error": Error,

    pub fn print(self: @This(), writer: *Writer) !void {
        switch (self) {
            .integer => |integer| try writer.print("{}\n", .{ integer.value }),
            .boolean => |boolean| try writer.print("{}\n", .{ boolean.value }),
            .@"null" => try writer.print("null\n", .{}),
            .@"return" => |@"return"| try @"return".value.print(writer),
            .@"error" => |@"error"| try writer.print("{}:{} {s}\n", .{@"error".line, @"error".column, @"error".message})
        }
    }
};

pub const Error = struct{
    line: usize,
    column: usize,
    message: []const u8,
};

pub const Return = struct{
    value: *Object
};

pub const Integer = struct{
    value: i64,
};


pub const Boolean = struct{
    value: bool,
};

pub const Null = struct{};

pub const Environment = struct{
    bindings: StringHashMap(*Object),
    arena: Allocator,

    pub fn init(arena: Allocator) @This() {
        return @This(){
            .bindings = StringHashMap(*Object).init(arena),
            .arena = arena,
        };
    }

    pub fn put(self: *@This(), identifier: []const u8, obj: *Object) !void {
        const key = try self.arena.alloc(u8, identifier.len);
        std.mem.copyForwards(u8, key, identifier);

        switch (obj.*) {
            .integer => {
                const value = try self.arena.create(Object);
                value.* = obj.*;
                try self.bindings.put(key, value);
            },
            else => {
                try self.bindings.put(key, obj);
            }
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
                }
            }
        } else {
            return null;
        }
    }

    pub fn deinit(self: *@This()) void {
        self.bindings.deinit();
    }
};
