const std = @import("std");
const ast = @import("ast.zig");
const monkeyScanner = @import("scanner.zig");

const Scanner = monkeyScanner.Scanner;
const assertTokensEqual = monkeyScanner.assertTokensEqual;
const Token = monkeyScanner.Token;
const TokenType = monkeyScanner.TokenType;
const Literal = monkeyScanner.Literal;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Reader = std.Io.Reader;

pub const ParserError = error{
    UnexpectedTokenError,
};

pub const Parser = struct {
    allocator: Allocator,
    scanner: *Scanner,
    current: Token,
    ahead: Token,

    pub fn init(allocator: Allocator, scanner: *Scanner) !@This() {
        return @This(){
            .allocator = allocator,
            .scanner = scanner,
            .current = try scanner.nextToken(),
            .ahead = try scanner.nextToken(),
        };
    }

    fn nextToken(self: *@This()) !void {
        self.current = self.ahead;
        self.ahead = try self.scanner.nextToken();
    }

    fn expectCurrentToken(self: *@This(), expect: TokenType) !void {
        if (self.current.type != expect) return ParserError.UnexpectedTokenError;
    }
    fn expectAheadToken(self: *@This(), expect: TokenType) !void {
        if (self.ahead.type != expect) return ParserError.UnexpectedTokenError;
    }

    fn parseExpression(self: *@This()) ?ast.Expression {
        switch (self.current.type) {
            TokenType.IDENT => return ast.Expression{ .identifier = self.parseIdentifier() orelse return null },
            TokenType.INT => return ast.Expression{ .integer = self.parseInteger() orelse return null },
            else => return null,
        }
    }

    fn parseIdentifier(self: *@This()) ?ast.Identifier {
        self.expectCurrentToken(TokenType.IDENT) catch return null;
        return ast.Identifier{
            .token = self.current,
            .name = self.current.literal,
        };
    }

    fn parseInteger(self: *@This()) ?ast.Integer {
        self.expectCurrentToken(TokenType.INT) catch return null;
        return ast.Integer{
            .token = self.current,
            .value = std.fmt.parseInt(i64, self.current.literal, 0) catch unreachable,
        };
    }

    fn parseLetStatement(self: *@This()) !?ast.LetStatement {
        const token = self.current;

        self.expectAheadToken(TokenType.IDENT) catch return null;
        try self.nextToken();

        const identifier = self.parseIdentifier() orelse return null;

        self.expectAheadToken(TokenType.ASSIGN) catch return null;
        try self.nextToken();

        try self.nextToken();

        const expression = self.parseExpression() orelse return null;

        return ast.LetStatement{
            .token = token,
            .identifier = identifier,
            .expression = expression,
        };
    }

    pub fn parseProgram(self: *@This()) !ast.Program {
        var statements: ArrayList(ast.Statement) = .empty;
        errdefer statements.deinit(self.allocator);

        while (self.current.type != TokenType.EOF) {
            var statement: ?ast.Statement = null;

            switch (self.current.type) {
                TokenType.LET => {
                    const letStatement = try self.parseLetStatement();
                    if (letStatement) |ls| statement = ast.Statement{ .letStatement = ls };
                },
                else => {},
            }

            if (statement) |s| {
                try statements.append(self.allocator, s);
            }

            try self.nextToken();
        }

        return ast.Program{ .statements = try statements.toOwnedSlice(self.allocator) };
    }
};

// pub fn programCleanup(program: ast.Program) void {}

fn expectLetStatement(statement: ast.Statement, name: []const u8) !void {
    switch (statement) {
        .letStatement => |ls| {
            try std.testing.expect(std.mem.eql(u8, ls.token.literal, "let"));
            try std.testing.expect(std.mem.eql(u8, ls.identifier.name, name));
            try std.testing.expect(std.mem.eql(u8, ls.identifier.token.literal, name));
        },
        else => try std.testing.expect(false),
    }
}

test "parse let statements" {
    const input =
        \\let num = 5;
        \\let ankka = num;
        \\let number = 15;
    ;

    const Case = struct {
        name: []const u8,
    };

    const cases = [_]Case{
        Case{
            .name = "num",
        },
        Case{
            .name = "ankka",
        },
        Case{
            .name = "number",
        },
    };

    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var scanner: Scanner = try .init(allocator, Reader.fixed(input));
    defer scanner.deinit();

    var parser: Parser = try .init(allocator, &scanner);

    const program: ast.Program = try parser.parseProgram();

    try std.testing.expect(program.statements.len == cases.len);

    for (program.statements, cases) |statement, case| {
        try expectLetStatement(statement, case.name);
    }
}
