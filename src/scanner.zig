const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const Reader = std.io.Reader;
const Writer = std.io.Writer;

pub const TokenType = enum { LPAREN, RPAREN, LBRACE, RBRACE, LBRACKET, RBRACKET, SEMICOLON, PLUS, MINUS, ASTERISK, SLASH, EQUALS, NOT_EQUALS, ASSIGN, BANG, COMMA, TRUE, FALSE, LET, RETURN, FN, IDENT, INT, EOF, ILLEGAL };

pub const Token = struct {
    type: TokenType,
    literal: []const u8,
    line: usize,
    column: usize,
};

const ScannerError = error{EOFError};

pub fn printToken(writer: *Writer, token: Token) !void {
    try writer.print("Token {{ type = {}, ", .{token.type});
    switch (token.literal) {
        .char => |c| try writer.print("char = '{c}', ", .{c}),
        .string => |s| try writer.print("string = \"{s}\", ", .{s}),
    }
    try writer.print("line = {}, column = {} }}\n", .{ token.line, token.column });
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
            self.column = 1;
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

    pub fn deinit(self: *@This()) void {
        self.keywords.deinit();
    }

    fn eatWhitespace(self: *@This()) void {
        while (std.ascii.isWhitespace(self.current)) self.nextChar();
    }

    fn readIdent(self: *@This()) ![]const u8 {
        var buffer: ArrayList(u8) = .empty;
        errdefer buffer.deinit(self.allocator);

        while (std.ascii.isAlphanumeric(self.current)) {
            try buffer.append(self.allocator, self.current);
            self.nextChar();
        }

        return buffer.toOwnedSlice(self.allocator);
    }

    fn readNumber(self: *@This()) ![]const u8 {
        var buffer: ArrayList(u8) = .empty;
        errdefer buffer.deinit(self.allocator);

        while (std.ascii.isDigit(self.current)) {
            try buffer.append(self.allocator, self.current);
            self.nextChar();
        }

        return buffer.toOwnedSlice(self.allocator);
    }

    fn createToken(self: *@This(), @"type": TokenType, literal: []const u8) Token {
        return Token{ .type = @"type", .literal = literal, .line = self.line, .column = self.column };
    }

    pub fn nextToken(self: *@This()) !Token {
        self.eatWhitespace();

        var token: Token = undefined;

        switch (self.current) {
            ';' => token = self.createToken(TokenType.SEMICOLON, ";"),
            '{' => token = self.createToken(TokenType.LBRACE, "{"),
            '}' => token = self.createToken(TokenType.RBRACE, "}"),
            '(' => token = self.createToken(TokenType.LPAREN, "("),
            ')' => token = self.createToken(TokenType.RPAREN, ")"),
            '[' => token = self.createToken(TokenType.LBRACKET, "["),
            ']' => token = self.createToken(TokenType.RBRACKET, "]"),
            '+' => token = self.createToken(TokenType.PLUS, "+"),
            '-' => token = self.createToken(TokenType.MINUS, "-"),
            '*' => token = self.createToken(TokenType.ASTERISK, "*"),
            '/' => token = self.createToken(TokenType.SLASH, "/"),
            ',' => token = self.createToken(TokenType.COMMA, ","),
            '!' => {
                if (self.ahead == '=') {
                    token = self.createToken(TokenType.NOT_EQUALS, "!=");
                    self.nextChar();
                } else {
                    token = self.createToken(TokenType.BANG, "!");
                }
            },
            '=' => {
                if (self.ahead == '=') {
                    token = self.createToken(TokenType.EQUALS, "==");
                    self.nextChar();
                } else {
                    token = self.createToken(TokenType.ASSIGN, "=");
                }
            },
            0 => token = self.createToken(TokenType.EOF, ""),
            else => {
                const line: usize = self.line;
                const column: usize = self.column;

                if (std.ascii.isAlphabetic(self.current)) {
                    const literal = try self.readIdent();

                    if (self.keywords.get(literal)) |@"type"| {
                        defer self.allocator.free(literal);
                        return Token{ .type = @"type", .literal = self.keywords.getKey(literal).?, .line = line, .column = column };
                    } else {
                        return Token{ .type = TokenType.IDENT, .literal = literal, .line = line, .column = column };
                    }
                } else if (std.ascii.isDigit(self.current)) {
                    const number = try self.readNumber();
                    return Token{ .type = TokenType.INT, .literal = number, .line = line, .column = column };
                }
                token = self.createToken(TokenType.ILLEGAL, "");
            },
        }

        self.nextChar();

        return token;
    }
};

pub fn assertTokensEqual(token: Token, case: Token) !void {
    try std.testing.expect(token.type == case.type);
    try std.testing.expect(std.mem.eql(u8, token.literal, case.literal));
    try std.testing.expect(token.line == case.line);
    try std.testing.expect(token.column == case.column);
}

//  test "one character tokens" {
//      const cases = [_]Token{ Token{
//          .type = TokenType.LBRACKET,
//          .literal = "[",
//          .line = 1,
//          .column = 2,
//      }, Token{
//          .type = TokenType.RBRACKET,
//          .literal = "]",
//          .line = 1,
//          .column = 4,
//      }, Token{
//          .type = TokenType.LBRACE,
//          .literal = "{",
//          .line = 1,
//          .column = 5,
//      }, Token{
//          .type = TokenType.RBRACE,
//          .literal = "}",
//          .line = 1,
//          .column = 7,
//      }, Token{
//          .type = TokenType.LPAREN,
//          .literal = "(",
//          .line = 1,
//          .column = 10,
//      }, Token{
//          .type = TokenType.RPAREN,
//          .literal = ")",
//          .line = 1,
//          .column = 13,
//      }, Token{
//          .type = TokenType.SEMICOLON,
//          .literal = ";",
//          .line = 2,
//          .column = 2,
//      }, Token{
//          .type = TokenType.SEMICOLON,
//          .literal = ";",
//          .line = 2,
//          .column = 3,
//      }, Token{
//          .type = TokenType.EOF,
//          .literal = "",
//          .line = 2,
//          .column = 4,
//      } };
//
//      var scanner = Scanner.init(std.testing.allocator,
//          \\ [ ]{ }  (  )
//          \\ ;;
//      );
//
//      for (cases) |case| {
//          const token = scanner.nextToken();
//          try assertTokensEqual(token, case);
//      }
//
//      const token = scanner.nextToken();
//      try std.testing.expect(token.type == TokenType.EOF);
//  }
//
//  test "two character tokens" {
//      const cases = [_]Token{ Token{
//          .type = TokenType.EQUALS,
//          .literal = "==",
//          .line = 1,
//          .column = 1,
//      }, Token{
//          .type = TokenType.NOT_EQUALS,
//          .literal = "!=",
//          .line = 2,
//          .column = 3,
//      }, Token{
//          .type = TokenType.EOF,
//          .literal = "",
//          .line = 2,
//          .column = 5,
//      } };
//
//      var scanner = Scanner.init(std.testing.allocator,
//          \\==
//          \\  !=
//      );
//
//      for (cases) |case| {
//          const token = scanner.nextToken();
//          try assertTokensEqual(token, case);
//      }
//
//      const token = scanner.nextToken();
//      try std.testing.expect(token.type == TokenType.EOF);
//  }
