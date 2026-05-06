const std = @import("std");

const Writer = std.Io.Writer;

pub const ObjectType = enum{
    INT,
    BOOL,
    NULL
};

pub const Object = union(enum){
    integer: Integer,
    boolean: Boolean,
    @"null": Null,
    @"return": Return,

    pub fn print(self: @This(), writer: *Writer) !void {
        switch (self) {
            .integer => |integer| try writer.print("{}\n", .{ integer.value }),
            .boolean => |boolean| try writer.print("{}\n", .{ boolean.value }),
            .@"null" => try writer.print("null\n", .{}),
            .@"return" => |@"return"| try @"return".value.print(writer),
        }
    }
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
