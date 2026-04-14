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
const AutoHashMap = std.AutoArrayHashMap;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;
const print = std.debug.print;

pub const ParserError = error{
    UnexpectedTokenError,
};

pub const Parser = struct {
    allocator: Allocator,
    scanner: *Scanner,
    current: Token,
    ahead: Token,
    errors: ArrayList([]const u8),
    
    const LOWEST = 0;
    const SUM = 1;
    const PRODUCT = 2;
    const CALL = 3;
    
    pub fn init(allocator: Allocator, scanner: *Scanner) !@This() {
        return @This(){
            .allocator = allocator,
            .scanner = scanner,
            .current = try scanner.nextToken(),
            .ahead = try scanner.nextToken(),
            .errors = ArrayList([]const u8).empty,
        };
    }

    fn nextToken(self: *@This()) !void {
        self.current = self.ahead;
        self.ahead = try self.scanner.nextToken();
    }

    fn currentTokenIs(self: *@This(), expect: TokenType) bool {
        return self.current.type == expect;
    }

    fn aheadTokenIs(self: *@This(), expect: TokenType) bool {
        return self.ahead.type == expect;
    }

    fn expectAhead(self: *@This(), expect: TokenType) !bool {
        if (self.aheadTokenIs(expect)) {
            try self.nextToken();
            return true;
        } else {
            const format = "Unexpected token of type '{}' found when '{}' was expected.";
            const errorMsg = try std.fmt.allocPrint(self.allocator, format, .{ self.ahead.type, expect });
            try self.errors.append(self.allocator, errorMsg);
            return false;
        }
    }

    fn parseIdentifier(self: *@This()) ?ast.Identifier {
        return ast.Identifier{
            .token = self.current,
            .name = self.current.literal,
        };
    }

    fn parseInteger(self: *@This()) ?ast.Integer {
        return ast.Integer{
            .token = self.current,
            .value = std.fmt.parseInt(i64, self.current.literal, 0) catch unreachable,
        };
    }

    fn parseInfix(self: *@This(), left: ast.Expression) !?ast.Infix {
        const token = self.current;

        const operator: ast.InfixOperator = switch (token.type) {
            TokenType.PLUS => ast.InfixOperator.ADD,
            TokenType.MINUS => ast.InfixOperator.SUBTRACT,
            TokenType.ASTERISK => ast.InfixOperator.MULTIPLY,
            TokenType.SLASH => ast.InfixOperator.DIVIDE,
            else => unreachable,
        };

        try self.nextToken();

        const right = try self.parseExpression() orelse return null;

        return ast.Infix{
            .token = token,
            .operator = operator,
            .left = left,
            .right = right,
        };
    }

    fn parseExpression(self: *@This()) !?ast.Expression {

        switch (self.current.type) {
            TokenType.IDENT => return ast.Expression{ .identifier = self.parseIdentifier() orelse return null },
            TokenType.INT => return ast.Expression{ .integer = self.parseInteger() orelse return null },
            else => return null,
        }

//      var left: ast.Expression = switch (self.current.type) {
//          TokenType.IDENT => ast.Expression{ .identifier = self.parseIdentifier() orelse return null },
//          TokenType.INT => ast.Expression{ .integer = self.parseInteger() orelse return null },
//          else => return null,
//      };
//
//      while (!self.aheadTokenIs(TokenType.SEMICOLON)) {
//          try self.nextToken();
//          left = ast.Expression{
//              .infix = switch (self.current.type) {
//                  TokenType.PLUS => try self.parseInfix(left) orelse return null,
//                  TokenType.MINUS => try self.parseInfix(left) orelse return null,
//                  TokenType.ASTERISK => try self.parseInfix(left) orelse return null,
//                  TokenType.SLASH => try self.parseInfix(left) orelse return null,
//                  else => unreachable,
//              }
//          };
//      }
//
//      return left;
    }

    fn parseLetStatement(self: *@This()) !?ast.LetStatement {
        const token = self.current;

        if (!try self.expectAhead(TokenType.IDENT)) return null;

        const identifier = self.parseIdentifier() orelse return null;

        if (!try self.expectAhead(TokenType.ASSIGN)) return null;

        try self.nextToken();

        const expression = try self.parseExpression() orelse return null;

        if (!try self.expectAhead(TokenType.SEMICOLON)) return null;

        return ast.LetStatement{
            .token = token,
            .identifier = identifier,
            .expression = expression,
        };
    }

    fn parseReturnStatement(self: *@This()) !?ast.ReturnStatement {
        const token = self.current;

        try self.nextToken();

        const expression = try self.parseExpression() orelse return null;

        if (!try self.expectAhead(TokenType.SEMICOLON)) return null;

        return ast.ReturnStatement{
            .token = token,
            .expression = expression,
        };
    }

    fn parseExpressionStatement(self: *@This()) !?ast.ExpressionStatement {
        return ast.ExpressionStatement{
            .token = self.current,
            .expression = try self.parseExpression() orelse return null,
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
                TokenType.RETURN => {
                    const returnStatement = try self.parseReturnStatement();
                    if (returnStatement) |rs| statement = ast.Statement{ .returnStatement = rs };
                },
                else => {
                    const expressionStatement = try self.parseExpressionStatement();
                    if (expressionStatement) |es| statement = ast.Statement{ .expressionStatement = es };
                },
            }

            if (statement) |s| {
                try statements.append(self.allocator, s);
            }

            try self.nextToken();
        }

        return ast.Program{ .statements = try statements.toOwnedSlice(self.allocator) };
    }

    pub fn printErrors(self: @This(), writer: *Writer) !void {
        for (self.errors.items) |err| {
            try writer.print("{s}\n", .{err});
        }
    }
};

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

test "parse statements" {
    const input =
        \\let num = 5;
        \\let ankka = num;
        \\return ankka;
    ;

    const cases = [_]ast.Statement{
        ast.Statement{
            .letStatement = ast.LetStatement{
                .token = Token{
                    .type = TokenType.LET,
                    .literal = "let",
                    .line = 1,
                    .column = 1
                },
                .identifier = ast.Identifier{ 
                    .token = Token{
                        .type = TokenType.IDENT,
                        .literal = "num",
                        .line = 1,
                        .column = 5,
                    },
                    .name = "num"
                },
                .expression = ast.Expression{
                    .integer = ast.Integer{
                        .token = Token{
                            .type = TokenType.INT,
                            .literal = "5",
                            .line = 1,
                            .column = 11,
                        },
                        .value = 5,
                    }
                },
            }
        },
        ast.Statement{
            .letStatement = ast.LetStatement{
                .token = Token{
                    .type = TokenType.LET,
                    .literal = "let",
                    .line = 2,
                    .column = 1
                },
                .identifier = ast.Identifier{ 
                    .token = Token{
                        .type = TokenType.IDENT,
                        .literal = "ankka",
                        .line = 2,
                        .column = 5,
                    },
                    .name = "ankka"
                },
                .expression = ast.Expression{
                    .identifier = ast.Identifier{
                        .token = Token{
                            .type = TokenType.IDENT,
                            .literal = "num",
                            .line = 2,
                            .column = 13,
                        },
                        .name = "num",
                    }
                },
            }
        },
        ast.Statement{
            .returnStatement = ast.ReturnStatement{
                .token = Token{
                    .type = TokenType.RETURN,
                    .literal = "return",
                    .line = 3,
                    .column = 1,
                },
                .expression = ast.Expression{
                    .identifier = ast.Identifier{
                        .token = Token{
                            .type = TokenType.IDENT,
                            .literal = "ankka",
                            .line = 3,
                            .column = 8,
                        },
                        .name = "ankka",
                    }
                }
            }
        }
    };

    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var scanner: Scanner = try .init(allocator, Reader.fixed(input));
    defer scanner.deinit();

    var parser: Parser = try .init(allocator, &scanner);

    const program: ast.Program = try parser.parseProgram();

    try std.testing.expectEqual(cases.len, program.statements.len);

    for (program.statements, cases) |statement, case| {
        try std.testing.expectEqualDeep(case, statement);
    }
}

