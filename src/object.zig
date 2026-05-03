const std = @import("std");

const Writer = std.io.Writer;

pub const ObjectType = enum{
    INT,
    BOOL,
    NULL
};

pub const Object = union(enum){
    integer: Integer,
    boolean: Boolean,
    @"null": Null,

    pub fn print(self: @This(), writer: *Writer) !void {
        switch (self) {
            .integer => |integer| try writer.print("{}\n", .{ integer.value }),
            .boolean => |boolean| try writer.print("{}\n", .{ boolean.value }),
            .@"null" => |_| try writer.print("null\n", .{}),
        }
    }
};

pub const Integer = struct{
    value: i64,

    pub fn getType() ObjectType {
        return .INT;
    }
};


pub const Boolean = struct{
    value: bool,

    pub fn getType() ObjectType {
        return .BOOL;
    }
};

pub const Null = struct{
    pub fn getType() ObjectType {
        return .NULL;
    }
};
