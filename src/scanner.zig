const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

pub const TokenType = enum { 
    LPAREN, 
    RPAREN, 
    LBRACE, 
    RBRACE, 
    LBRACKET, 
    RBRACKET, 
    SEMICOLON, 
    PLUS, 
    MINUS, 
    ASTERISK, 
    SLASH, 
    EQUALS, 
    NOT_EQUALS, 
    ASSIGN, 
    BANG, 
    COMMA, 

    TRUE,
    FALSE,
    LET, 
    RETURN, 
    FN, 

    IDENT, 
    INT, 

    EOF, 
    ILLEGAL 
};

pub const Literal = union(enum) {
    char: u8,
    string: []const u8,
};

pub const Token = struct {
    type: TokenType,
    literal: Literal,
    line: usize,
    column: usize,
};

const IDENT_MAX_SIZE = 255;

const ScannerError = error{EOFError};

pub fn printToken(token: Token) void {
    std.debug.print("Token {{ type = {}, ", .{ token.type });
    switch (token.literal) {
        .char => |c| std.debug.print("char = '{c}', ", .{ c }), 
        .string => |s| std.debug.print("string = \"{s}\", ", .{ s }), 
    }
    std.debug.print("line = {}, column = {} }}\n", .{ token.line, token.column });
}

pub const Scanner = struct {

    allocator: Allocator,
    sourceCode: []const u8,

    current: usize,
    ahead: usize,

    line: usize,
    column: usize,

    keywords: StringHashMap(TokenType),

    fn getCurrentChar(self: *@This()) ScannerError!u8 {
        return if (self.current < self.sourceCode.len) self.sourceCode[self.current] else ScannerError.EOFError;
    }

    fn getAheadChar(self: *@This()) ScannerError!u8 {
        return if (self.ahead < self.sourceCode.len) self.sourceCode[self.ahead] else ScannerError.EOFError;
    }

    fn nextChar(self: *@This()) ScannerError!void {
        if (self.current < self.sourceCode.len) {
            self.current += 1;
            self.ahead = self.current + 1;

            self.column += 1;

            if (try self.getCurrentChar() == '\n') {
                self.column = 0;
                self.line += 1;
            }
        }
    }

    pub fn init(allocator: Allocator, source_code: []const u8) !@This() {

        var keywords: StringHashMap(TokenType) = .init(allocator);

        try keywords.put("let", TokenType.LET);
        try keywords.put("return", TokenType.RETURN);
        try keywords.put("true", TokenType.TRUE);
        try keywords.put("false", TokenType.FALSE);
        try keywords.put("fn", TokenType.FN);

        return Scanner{
            .allocator = allocator,
            .sourceCode = source_code,
            .current = 0,
            .ahead = 1,
            .line = 1,
            .column = 1,
            .keywords = keywords
        };
    }

    fn eatWhitespace(self: *@This()) ScannerError!void {
        while (std.ascii.isWhitespace(try self.getCurrentChar())) try self.nextChar();
    }

    fn readIdent(self: *@This()) ![]const u8 {
        var buffer: ArrayList(u8) = .empty;

        var current = self.getCurrentChar() catch unreachable;
        while (std.ascii.isAlphanumeric(current)) {
            try buffer.append(self.allocator, current);
            self.nextChar() catch return buffer.toOwnedSlice(self.allocator);
            current = self.getCurrentChar() catch return buffer.toOwnedSlice(self.allocator);
        }

        return buffer.toOwnedSlice(self.allocator);
    }

    fn readNumber(self: *@This()) ![]const u8 {
        var buffer: ArrayList(u8) = .empty;

        var current = self.getCurrentChar() catch unreachable;
        while (std.ascii.isDigit(current)) {
            try buffer.append(self.allocator, current);
            self.nextChar() catch return buffer.toOwnedSlice(self.allocator);
            current = self.getCurrentChar() catch return buffer.toOwnedSlice(self.allocator);
        }

        return buffer.toOwnedSlice(self.allocator);
    }

    fn createToken(self: *@This(), @"type": TokenType, literal: Literal) Token {
        return Token{ .type = @"type", .literal = literal, .line = self.line, .column = self.column };
    }

    pub fn nextToken(self: *@This()) !Token {
        self.eatWhitespace() catch {
            return self.createToken(TokenType.EOF, Literal{ .char = 0 });
        };

        var token: Token = undefined;

        const current = self.getCurrentChar() catch {
            return self.createToken(TokenType.EOF, Literal{ .char = 0 });
        };

        const ahead = self.getAheadChar() catch 0;

        token_switch: switch (current) {
            ';' => token = self.createToken(TokenType.SEMICOLON, Literal{ .char = current }),
            '{' => token = self.createToken(TokenType.LBRACE, Literal{ .char = current }),
            '}' => token = self.createToken(TokenType.RBRACE, Literal{ .char = current }),
            '(' => token = self.createToken(TokenType.LPAREN, Literal{ .char = current }),
            ')' => token = self.createToken(TokenType.RPAREN, Literal{ .char = current }),
            '[' => token = self.createToken(TokenType.LBRACKET, Literal{ .char = current }),
            ']' => token = self.createToken(TokenType.RBRACKET, Literal{ .char = current }),
            '+' => token = self.createToken(TokenType.PLUS, Literal{ .char = current }),
            '-' => token = self.createToken(TokenType.MINUS, Literal{ .char = current }),
            '*' => token = self.createToken(TokenType.ASTERISK, Literal{ .char = current }),
            '/' => token = self.createToken(TokenType.SLASH, Literal{ .char = current }),
            ',' => token = self.createToken(TokenType.COMMA, Literal{ .char = current }),
            '!' => {
                if (ahead == '=') {
                    token = self.createToken(TokenType.NOT_EQUALS, Literal{ .string = "!=" });
                    self.nextChar() catch {};
                    break :token_switch;
                }
                token = self.createToken(TokenType.BANG, Literal{ .char = current });
            },
            '=' => {
                if (ahead == '=') {
                    token = self.createToken(TokenType.EQUALS, Literal{ .string = "==" });
                    self.nextChar() catch {};
                    break :token_switch;
                }
                token = self.createToken(TokenType.ASSIGN, Literal{ .char = current });
            },
            else => {
                const line: usize = self.line;
                const column: usize = self.column;

                if (std.ascii.isAlphabetic(current)) {
                    const literal = try self.readIdent(); 

                    if (self.keywords.get(literal)) |@"type"| {
                        defer self.allocator.free(literal);
                        return Token{ 
                            .type = @"type",
                            .literal = Literal { .string = self.keywords.getKey(literal).? }, 
                            .line = line, 
                            .column = column 
                        };
                    } else {
                        return Token{ .type = TokenType.IDENT, .literal = Literal { .string = literal }, .line = line, .column = column };
                    }
                    
                } else if (std.ascii.isDigit(current)) {
                    const number = try self.readNumber();
                    return Token{ .type = TokenType.INT, .literal = Literal { .string = number }, .line = line, .column = column };
                }
                token = self.createToken(TokenType.ILLEGAL, Literal{ .char = current });
            },
        }

        self.nextChar() catch {};

        return token;
    }
};

fn assertTokensEqual(token: Token, case: Token) !void {
    try std.testing.expect(token.type == case.type);
    try std.testing.expect(std.mem.eql(u8, token.literal, case.literal));
    try std.testing.expect(token.line == case.line);
    try std.testing.expect(token.column == case.column);
}

test "one character tokens" {
    const cases = [_]Token{ Token{
        .type = TokenType.LBRACKET,
        .literal = "[",
        .line = 1,
        .column = 2,
    }, Token{
        .type = TokenType.RBRACKET,
        .literal = "]",
        .line = 1,
        .column = 4,
    }, Token{
        .type = TokenType.LBRACE,
        .literal = "{",
        .line = 1,
        .column = 5,
    }, Token{
        .type = TokenType.RBRACE,
        .literal = "}",
        .line = 1,
        .column = 7,
    }, Token{
        .type = TokenType.LPAREN,
        .literal = "(",
        .line = 1,
        .column = 10,
    }, Token{
        .type = TokenType.RPAREN,
        .literal = ")",
        .line = 1,
        .column = 13,
    }, Token{
        .type = TokenType.SEMICOLON,
        .literal = ";",
        .line = 2,
        .column = 2,
    }, Token{
        .type = TokenType.SEMICOLON,
        .literal = ";",
        .line = 2,
        .column = 3,
    }, Token{
        .type = TokenType.EOF,
        .literal = "",
        .line = 2,
        .column = 4,
    } };

    var scanner = Scanner.init(
        std.testing.allocator,
        \\ [ ]{ }  (  )  
        \\ ;;
    );

    for (cases) |case| {
        const token = scanner.nextToken();
        try assertTokensEqual(token, case);
    }

    const token = scanner.nextToken();
    try std.testing.expect(token.type == TokenType.EOF);
}

test "two character tokens" {
    const cases = [_]Token{
        Token{
            .type = TokenType.EQUALS,
            .literal = "==",
            .line = 1,
            .column = 1,
        },
        Token{
            .type = TokenType.NOT_EQUALS,
            .literal = "!=",
            .line = 2,
            .column = 3,
        },
        Token{
            .type = TokenType.EOF,
            .literal = "",
            .line = 2,
            .column = 5,
        }
    };

    var scanner = Scanner.init(
        std.testing.allocator,
        \\==
        \\  !=
    );

    for (cases) |case| {
        const token = scanner.nextToken();
        try assertTokensEqual(token, case);
    }

    const token = scanner.nextToken();
    try std.testing.expect(token.type == TokenType.EOF);

}
