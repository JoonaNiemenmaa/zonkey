const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const Reader = std.io.Reader;

pub const TokenType = enum { LPAREN, RPAREN, LBRACE, RBRACE, LBRACKET, RBRACKET, SEMICOLON, PLUS, MINUS, ASTERISK, SLASH, EQUALS, NOT_EQUALS, ASSIGN, BANG, COMMA, TRUE, FALSE, LET, RETURN, FN, IDENT, INT, EOF, ILLEGAL };

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

const ScannerError = error{EOFError};

pub fn printToken(token: Token) void {
    std.debug.print("Token {{ type = {}, ", .{token.type});
    switch (token.literal) {
        .char => |c| std.debug.print("char = '{c}', ", .{c}),
        .string => |s| std.debug.print("string = \"{s}\", ", .{s}),
    }
    std.debug.print("line = {}, column = {} }}\n", .{ token.line, token.column });
}

pub const Scanner = struct {
    allocator: Allocator,
    reader: Reader,

    current: u8,
    ahead: u8,

    line: usize,
    column: usize,

    keywords: StringHashMap(TokenType),

    fn nextChar(self: *@This()) void {
        self.current = self.ahead;
        self.ahead = self.reader.takeByte() catch 0;

        self.column += 1;

        if (self.current == '\n') {
            self.column += 1;
            self.line += 1;
        }
    }

    pub fn init(allocator: Allocator, reader: Reader) !@This() {
        var keywords: StringHashMap(TokenType) = .init(allocator);

        try keywords.put("let", TokenType.LET);
        try keywords.put("return", TokenType.RETURN);
        try keywords.put("true", TokenType.TRUE);
        try keywords.put("false", TokenType.FALSE);
        try keywords.put("fn", TokenType.FN);

        var scanner = Scanner{ .allocator = allocator, .reader = reader, .current = 0, .ahead = 0, .line = 1, .column = 1, .keywords = keywords };

        scanner.current = scanner.reader.takeByte() catch 0;
        scanner.ahead = scanner.reader.takeByte() catch 0;

        return scanner;
    }

    fn eatWhitespace(self: *@This()) void {
        while (std.ascii.isWhitespace(self.current)) self.nextChar();
    }

    fn readIdent(self: *@This()) ![]const u8 {
        var buffer: ArrayList(u8) = .empty;

        while (std.ascii.isAlphanumeric(self.current)) {
            try buffer.append(self.allocator, self.current);
            self.nextChar();
        }

        return buffer.toOwnedSlice(self.allocator);
    }

    fn readNumber(self: *@This()) ![]const u8 {
        var buffer: ArrayList(u8) = .empty;

        while (std.ascii.isDigit(self.current)) {
            try buffer.append(self.allocator, self.current);
            self.nextChar();
        }

        return buffer.toOwnedSlice(self.allocator);
    }

    fn createToken(self: *@This(), @"type": TokenType, literal: Literal) Token {
        return Token{ .type = @"type", .literal = literal, .line = self.line, .column = self.column };
    }

    pub fn nextToken(self: *@This()) !Token {
        self.eatWhitespace();

        var token: Token = undefined;

        switch (self.current) {
            ';' => token = self.createToken(TokenType.SEMICOLON, Literal{ .char = self.current }),
            '{' => token = self.createToken(TokenType.LBRACE, Literal{ .char = self.current }),
            '}' => token = self.createToken(TokenType.RBRACE, Literal{ .char = self.current }),
            '(' => token = self.createToken(TokenType.LPAREN, Literal{ .char = self.current }),
            ')' => token = self.createToken(TokenType.RPAREN, Literal{ .char = self.current }),
            '[' => token = self.createToken(TokenType.LBRACKET, Literal{ .char = self.current }),
            ']' => token = self.createToken(TokenType.RBRACKET, Literal{ .char = self.current }),
            '+' => token = self.createToken(TokenType.PLUS, Literal{ .char = self.current }),
            '-' => token = self.createToken(TokenType.MINUS, Literal{ .char = self.current }),
            '*' => token = self.createToken(TokenType.ASTERISK, Literal{ .char = self.current }),
            '/' => token = self.createToken(TokenType.SLASH, Literal{ .char = self.current }),
            ',' => token = self.createToken(TokenType.COMMA, Literal{ .char = self.current }),
            '!' => {
                if (self.ahead == '=') {
                    token = self.createToken(TokenType.NOT_EQUALS, Literal{ .string = "!=" });
                    self.nextChar();
                } else {
                    token = self.createToken(TokenType.BANG, Literal{ .char = self.current });
                }
            },
            '=' => {
                if (self.ahead == '=') {
                    token = self.createToken(TokenType.EQUALS, Literal{ .string = "==" });
                    self.nextChar();
                } else {
                    token = self.createToken(TokenType.ASSIGN, Literal{ .char = self.current });
                }
            },
            0 => token = self.createToken(TokenType.EOF, Literal{ .char = self.current }),
            else => {
                const line: usize = self.line;
                const column: usize = self.column;

                if (std.ascii.isAlphabetic(self.current)) {
                    const literal = try self.readIdent();

                    if (self.keywords.get(literal)) |@"type"| {
                        defer self.allocator.free(literal);
                        return Token{ .type = @"type", .literal = Literal{ .string = self.keywords.getKey(literal).? }, .line = line, .column = column };
                    } else {
                        return Token{ .type = TokenType.IDENT, .literal = Literal{ .string = literal }, .line = line, .column = column };
                    }
                } else if (std.ascii.isDigit(self.current)) {
                    const number = try self.readNumber();
                    return Token{ .type = TokenType.INT, .literal = Literal{ .string = number }, .line = line, .column = column };
                }
                token = self.createToken(TokenType.ILLEGAL, Literal{ .char = self.current });
            },
        }

        self.nextChar();

        return token;
    }
};
