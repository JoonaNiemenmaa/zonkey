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

pub const Parser = struct {
    allocator: Allocator,
    scanner: *Scanner,
    current: Token,
    ahead: Token,
    errors: ArrayList([]const u8),

    fn appendError(self: *@This(), comptime format: []const u8, args: anytype) !void {
        const errorMsg = try std.fmt.allocPrint(self.allocator, format, args);
        try self.errors.append(self.allocator, errorMsg);
    }

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
            try self.appendError("Unexpected token of type '{}' found when '{}' was expected.", .{ self.ahead.type, expect });
            return false;
        }
    }

    fn parseIdentifier(self: *@This()) ast.Identifier {
        return ast.Identifier{
            .token = self.current,
            .name = self.current.literal,
        };
    }

    fn parseInteger(self: *@This()) ast.Integer {
        return ast.Integer{
            .token = self.current,
            .value = std.fmt.parseInt(i64, self.current.literal, 0) catch unreachable,
        };
    }

    fn parseBoolean(self: *@This()) ast.Boolean {
        return ast.Boolean{
            .token = self.current,
            .value = switch (self.current.type) {
                TokenType.TRUE => true,
                TokenType.FALSE => false,
                else => unreachable,
            },
        };
    }

    fn parseIf(self: *@This()) Allocator.Error!?ast.If {
        const token = self.current;

        if (!try self.expectAhead(TokenType.LPAREN)) return null;

        const condition = try self.parseGroupedExpression() orelse return null;

        if (!try self.expectAhead(TokenType.LBRACE)) return null;

        const consequence = try self.parseBlock();
        
        var alternative: ?ast.Block = null;

        if (self.aheadTokenIs(TokenType.ELSE)) {
            try self.nextToken();

            if (!try self.expectAhead(TokenType.LBRACE)) return null;

            alternative = try self.parseBlock();
        }

        return ast.If{
            .token = token,
            .condition = condition,
            .consequence = consequence,
            .alternative = alternative,
        };
    }

    fn parsePrefix(self: *@This(), operator: ast.PrefixOperator) Allocator.Error!?ast.Prefix {
        const token = self.current;

        try self.nextToken();

        const expression = try self.parseExpression(Precedence.PREFIX) orelse return null;

        return ast.Prefix{
            .token = token,
            .operator = operator,
            .operand = expression,
        };
    }

    fn parseInfix(self: *@This(), operator: ast.InfixOperator, left: *ast.Expression) Allocator.Error!?ast.Infix {
        const token = self.current;

        try self.nextToken();

        const right = try self.parseExpression(getPrecedence(token.type)) orelse return null;

        return ast.Infix{
            .token = token,
            .operator = operator,
            .left = left,
            .right = right,
        };
    }

    fn parseGroupedExpression(self: *@This()) !?*ast.Expression {
        try self.nextToken();

        const expression = try self.parseExpression(Precedence.LOWEST) orelse return null;

        if (!try self.expectAhead(TokenType.RPAREN)) return null;

        return expression;
    }

    const Precedence = enum(u8) {
        LOWEST = 0,
        EQUALS,
        LESSGREATER,
        SUM,
        PRODUCT,
        PREFIX,
        CALL,
    };

    fn getPrecedence(@"type": TokenType) Precedence {
        return switch (@"type") {
            TokenType.EQUALS => Precedence.EQUALS,
            TokenType.NOT_EQUALS => Precedence.EQUALS,
            TokenType.LESS_THAN => Precedence.LESSGREATER,
            TokenType.GREATER_THAN => Precedence.LESSGREATER,
            TokenType.PLUS => Precedence.SUM,
            TokenType.MINUS => Precedence.SUM,
            TokenType.ASTERISK => Precedence.PRODUCT,
            TokenType.SLASH => Precedence.PRODUCT,
            else => Precedence.LOWEST,
        };
    }

    fn parseExpression(self: *@This(), precedence: Precedence) Allocator.Error!?*ast.Expression {
        var left: *ast.Expression = try self.allocator.create(ast.Expression);
        errdefer self.allocator.destroy(left);

        left.* = switch (self.current.type) {
            TokenType.IDENT => ast.Expression{ .identifier = self.parseIdentifier() },
            TokenType.INT => ast.Expression{ .integer = self.parseInteger() },
            TokenType.FALSE => ast.Expression{ .boolean = self.parseBoolean() },
            TokenType.TRUE => ast.Expression{ .boolean = self.parseBoolean() },
            TokenType.MINUS => ast.Expression{ .prefix = try self.parsePrefix(ast.PrefixOperator.MINUS) orelse return null },
            TokenType.BANG => ast.Expression{ .prefix = try self.parsePrefix(ast.PrefixOperator.NOT) orelse return null },
            TokenType.LPAREN => (try self.parseGroupedExpression() orelse return null).*,
            TokenType.IF => ast.Expression{ .@"if" = try self.parseIf() orelse return null },
            else => {
                try self.appendError("Unexpected token of type '{}' found when expression was expected.", .{self.current.type});
                return null;
            },
        };

        while (!self.aheadTokenIs(TokenType.SEMICOLON) and
            !self.aheadTokenIs(TokenType.EOF) and
            !self.aheadTokenIs(TokenType.RPAREN) and
            @intFromEnum(precedence) < @intFromEnum(getPrecedence(self.ahead.type)))
        {
            try self.nextToken();
            const infix = try self.allocator.create(ast.Expression);
            errdefer self.allocator.destroy(infix);

            infix.* = ast.Expression{
                .infix = switch (self.current.type) {
                    TokenType.PLUS => try self.parseInfix(ast.InfixOperator.ADD, left) orelse return null,
                    TokenType.MINUS => try self.parseInfix(ast.InfixOperator.SUBTRACT, left) orelse return null,
                    TokenType.ASTERISK => try self.parseInfix(ast.InfixOperator.MULTIPLY, left) orelse return null,
                    TokenType.SLASH => try self.parseInfix(ast.InfixOperator.DIVIDE, left) orelse return null,
                    TokenType.LESS_THAN => try self.parseInfix(ast.InfixOperator.LESS_THAN, left) orelse return null,
                    TokenType.GREATER_THAN => try self.parseInfix(ast.InfixOperator.GREATER_THAN, left) orelse return null,
                    TokenType.EQUALS => try self.parseInfix(ast.InfixOperator.EQUALS, left) orelse return null,
                    TokenType.NOT_EQUALS => try self.parseInfix(ast.InfixOperator.NOT_EQUALS, left) orelse return null,
                    else => unreachable,
                },
            };

            left = infix;
        }

        return left;
    }

    fn parseLetStatement(self: *@This()) !?ast.LetStatement {
        const token = self.current;

        if (!try self.expectAhead(TokenType.IDENT)) return null;

        const identifier = self.parseIdentifier();

        if (!try self.expectAhead(TokenType.ASSIGN)) return null;

        try self.nextToken();

        const expression = try self.parseExpression(Precedence.LOWEST) orelse return null;

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

        const expression = try self.parseExpression(Precedence.LOWEST) orelse return null;

        if (!try self.expectAhead(TokenType.SEMICOLON)) return null;

        return ast.ReturnStatement{
            .token = token,
            .expression = expression,
        };
    }

    fn parseExpressionStatement(self: *@This()) !?ast.ExpressionStatement {
        const token = self.current;
        const expression = try self.parseExpression(Precedence.LOWEST) orelse return null;

        if (self.aheadTokenIs(TokenType.SEMICOLON)) {
            try self.nextToken();
        }

        return ast.ExpressionStatement{
            .token = token,
            .expression = expression,
        };
    }

    fn parseBlock(self: *@This()) !ast.Block {
        const token = self.current;

        try self.nextToken();

        var statements: ArrayList(ast.Statement) = .empty;
        errdefer statements.deinit(self.allocator);

        while (!self.currentTokenIs(TokenType.RBRACE) and !self.currentTokenIs(TokenType.EOF)) {
            const statement = try self.parseStatement();

            if (statement) |s| try statements.append(self.allocator, s);

            try self.nextToken();
        }

        return ast.Block{
            .token = token,
            .statements = try statements.toOwnedSlice(self.allocator),
        };
    }

    fn parseStatement(self: *@This()) !?ast.Statement {
        switch (self.current.type) {
            TokenType.LET => {
                const letStatement = try self.parseLetStatement();
                if (letStatement) |ls| return ast.Statement{ .letStatement = ls };
            },
            TokenType.RETURN => {
                const returnStatement = try self.parseReturnStatement();
                if (returnStatement) |rs| return ast.Statement{ .returnStatement = rs };
            },
            else => {
                const expressionStatement = try self.parseExpressionStatement();
                if (expressionStatement) |es| return ast.Statement{ .expressionStatement = es };
            },
        }
        return null;
    }

    pub fn parseProgram(self: *@This()) !ast.Program {
        var statements: ArrayList(ast.Statement) = .empty;
        errdefer statements.deinit(self.allocator);

        while (self.current.type != TokenType.EOF) {
            const statement: ?ast.Statement = try self.parseStatement();

            if (statement) |s| try statements.append(self.allocator, s);

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

