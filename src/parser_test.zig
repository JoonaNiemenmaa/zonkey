const std = @import("std");
const ast = @import("ast.zig");
const monkeyScanner = @import("scanner.zig");
const monkeyParser = @import("parser.zig");

const Scanner = monkeyScanner.Scanner;
const Parser = monkeyParser.Parser;
const Token = monkeyScanner.Token;
const TokenType = monkeyScanner.TokenType;
const Literal = monkeyScanner.Literal;
const Reader = std.io.Reader;

test "parse statements" {
    const input =
        \\let num = 5;
        \\let ankka = num;
        \\return ankka;
    ;

    const cases = [_]ast.Statement{ ast.Statement{ .letStatement = ast.LetStatement{
        .token = Token{ .type = TokenType.LET, .literal = "let", .line = 1, .column = 1 },
        .identifier = ast.Identifier{ .token = Token{
            .type = TokenType.IDENT,
            .literal = "num",
            .line = 1,
            .column = 5,
        }, .name = "num" },
        .expression = &ast.Expression{ .integer = ast.Integer{
            .token = Token{
                .type = TokenType.INT,
                .literal = "5",
                .line = 1,
                .column = 11,
            },
            .value = 5,
        } },
    } }, ast.Statement{ .letStatement = ast.LetStatement{
        .token = Token{ .type = TokenType.LET, .literal = "let", .line = 2, .column = 1 },
        .identifier = ast.Identifier{ .token = Token{
            .type = TokenType.IDENT,
            .literal = "ankka",
            .line = 2,
            .column = 5,
        }, .name = "ankka" },
        .expression = &ast.Expression{ .identifier = ast.Identifier{
            .token = Token{
                .type = TokenType.IDENT,
                .literal = "num",
                .line = 2,
                .column = 13,
            },
            .name = "num",
        } },
    } }, ast.Statement{ .returnStatement = ast.ReturnStatement{ .token = Token{
        .type = TokenType.RETURN,
        .literal = "return",
        .line = 3,
        .column = 1,
    }, .expression = &ast.Expression{ .identifier = ast.Identifier{
        .token = Token{
            .type = TokenType.IDENT,
            .literal = "ankka",
            .line = 3,
            .column = 8,
        },
        .name = "ankka",
    } } } } };

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

test "test precedence" {
    const cases = [_]struct { @"test": []const u8, expect: []const u8 }{
        .{
            .@"test" = "1 + (2 + 3) + 4",
            .expect = "((1 + (2 + 3)) + 4)",
        },
        .{
            .@"test" = "(5 + 5) * 2",
            .expect = "((5 + 5) * 2)",
        },
        .{
            .@"test" = "2 / (5 + 5)",
            .expect = "(2 / (5 + 5))",
        },
        .{
            .@"test" = "-(5 + 5)",
            .expect = "(-(5 + 5))",
        },
        .{
            .@"test" = "!(true == true)",
            .expect = "(!(true == true))",
        },
    };

    for (cases) |case| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();

        const allocator = arena.allocator();

        var scanner: Scanner = try .init(allocator, Reader.fixed(case.@"test"));
        defer scanner.deinit();

        var parser: Parser = try .init(allocator, &scanner);

        const program: ast.Program = try parser.parseProgram();

        std.testing.expectEqual(1, program.statements.len) catch |err| {
            std.debug.print("case: {s}\n", .{case.expect});
            return err;
        };

        try std.testing.expectEqualSlices(u8, case.expect, try program.statements[0].string(allocator));
    }
}

test "test parsing expressions" {
    const input =
        \\5;
        \\joona;
        \\true;
        \\false;
        \\-5;
        \\!true;
        \\5 + 5;
        \\5 - 5;
    ;

    const cases = [_]ast.Statement{
        ast.Statement{
            .expressionStatement = ast.ExpressionStatement{
                .token = Token{
                    .type = TokenType.INT,
                    .literal = "5",
                    .line = 1,
                    .column = 1,
                },
                .expression = &ast.Expression{
                    .integer = ast.Integer{
                        .token = Token{
                            .type = TokenType.INT,
                            .literal = "5",
                            .line = 1,
                            .column = 1,
                        },
                        .value = 5,
                    }
                }
            }
        },
        ast.Statement{
            .expressionStatement = ast.ExpressionStatement{
                .token = Token{
                    .type = TokenType.IDENT,
                    .literal = "joona",
                    .line = 2,
                    .column = 1,
                },
                .expression = &ast.Expression{
                    .identifier = ast.Identifier{
                        .token = Token{
                            .type = TokenType.IDENT,
                            .literal = "joona",
                            .line = 2,
                            .column = 1,
                        },
                        .name = "joona",
                    }
                }
            }
        },
        ast.Statement{
            .expressionStatement = ast.ExpressionStatement{
                .token = Token{
                    .type = TokenType.TRUE,
                    .literal = "true",
                    .line = 3,
                    .column = 1,
                },
                .expression = &ast.Expression{
                    .boolean = ast.Boolean{
                        .token = Token{
                            .type = TokenType.TRUE,
                            .literal = "true",
                            .line = 3,
                            .column = 1,
                        },
                        .value = true,
                    }
                }
            }
        },
        ast.Statement{
            .expressionStatement = ast.ExpressionStatement{
                .token = Token{
                    .type = TokenType.FALSE,
                    .literal = "false",
                    .line = 4,
                    .column = 1,
                },
                .expression = &ast.Expression{
                    .boolean = ast.Boolean{
                        .token = Token{
                            .type = TokenType.FALSE,
                            .literal = "false",
                            .line = 4,
                            .column = 1,
                        },
                        .value = false,
                    }
                }
            }
        },
        ast.Statement{
            .expressionStatement = ast.ExpressionStatement{
                .token = Token{
                    .type = TokenType.MINUS,
                    .literal = "-",
                    .line = 5,
                    .column = 1,
                },
                .expression = &ast.Expression{
                    .prefix = ast.Prefix{
                        .token = Token{
                            .type = TokenType.MINUS,
                            .literal = "-",
                            .line = 5,
                            .column = 1,
                        },
                        .operator = ast.PrefixOperator.MINUS,
                        .operand = &ast.Expression{
                            .integer = ast.Integer{
                                .token = Token{
                                    .type = TokenType.INT,
                                    .literal = "5",
                                    .line = 5,
                                    .column = 2,
                                },
                                .value = 5,
                            }
                        }
                    }
                }
            }
        },
        ast.Statement{
            .expressionStatement = ast.ExpressionStatement{
                .token = Token{
                    .type = TokenType.BANG,
                    .literal = "!",
                    .line = 6,
                    .column = 1,
                },
                .expression = &ast.Expression{
                    .prefix = ast.Prefix{
                        .token = Token{
                            .type = TokenType.BANG,
                            .literal = "!",
                            .line = 6,
                            .column = 1,
                        },
                        .operator = ast.PrefixOperator.NOT,
                        .operand = &ast.Expression{
                            .boolean = ast.Boolean{
                                .token = Token{
                                    .type = TokenType.TRUE,
                                    .literal = "true",
                                    .line = 6,
                                    .column = 2,
                                },
                                .value = true,
                            }
                        }
                    }
                }
            }
        },
        ast.Statement{
            .expressionStatement = ast.ExpressionStatement{
                .token = Token{
                    .type = TokenType.INT,
                    .literal = "5",
                    .line = 7,
                    .column = 1,
                },
                .expression = &ast.Expression{
                    .infix = ast.Infix{
                        .token = Token{
                            .type = TokenType.PLUS,
                            .literal = "+",
                            .line = 7,
                            .column = 3,
                        },
                        .operator = ast.InfixOperator.ADD,
                        .left = &ast.Expression{
                            .integer = ast.Integer{
                                .token = Token{
                                    .type = TokenType.INT,
                                    .literal = "5",
                                    .line = 7,
                                    .column = 1,
                                },
                                .value = 5,
                            }
                        },
                        .right = &ast.Expression{
                            .integer = ast.Integer{
                                .token = Token{
                                    .type = TokenType.INT,
                                    .literal = "5",
                                    .line = 7,
                                    .column = 5,
                                },
                                .value = 5,
                            }
                        }
                    }
                }
            }
        },
        ast.Statement{
            .expressionStatement = ast.ExpressionStatement{
                .token = Token{
                    .type = TokenType.INT,
                    .literal = "5",
                    .line = 8,
                    .column = 1,
                },
                .expression = &ast.Expression{
                    .infix = ast.Infix{
                        .token = Token{
                            .type = TokenType.MINUS,
                            .literal = "-",
                            .line = 8,
                            .column = 3,
                        },
                        .operator = ast.InfixOperator.SUBTRACT,
                        .left = &ast.Expression{
                            .integer = ast.Integer{
                                .token = Token{
                                    .type = TokenType.INT,
                                    .literal = "5",
                                    .line = 8,
                                    .column = 1,
                                },
                                .value = 5,
                            }
                        },
                        .right = &ast.Expression{
                            .integer = ast.Integer{
                                .token = Token{
                                    .type = TokenType.INT,
                                    .literal = "5",
                                    .line = 8,
                                    .column = 5,
                                },
                                .value = 5,
                            }
                        }
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

test "test if expression" {
    const input =
        \\if (5 == 5) { return 5; }
        \\if (5 == 5) { return 5; } else { return 6; }
    ;

    const cases = [_]ast.Statement{
        ast.Statement{
            .expressionStatement = ast.ExpressionStatement{
                .token = Token{
                    .type = TokenType.IF,
                    .literal = "if",
                    .line = 1,
                    .column = 1,
                },
                .expression = &ast.Expression{
                    .@"if" = ast.If{
                        .token = Token{
                            .type = TokenType.IF,
                            .literal = "if",
                            .line = 1,
                            .column = 1,
                        },
                        .condition = &ast.Expression{
                            .infix = ast.Infix{
                                .token = Token{
                                    .type = TokenType.EQUALS,
                                    .literal = "==",
                                    .line = 1,
                                    .column = 7,
                                },
                                .operator = ast.InfixOperator.EQUALS,
                                .left = &ast.Expression{
                                    .integer = ast.Integer{
                                        .token = Token{
                                            .type = TokenType.INT,
                                            .literal = "5",
                                            .line = 1,
                                            .column = 5,
                                        },
                                        .value = 5,
                                    }
                                },
                                .right = &ast.Expression{
                                    .integer = ast.Integer{
                                        .token = Token{
                                            .type = TokenType.INT,
                                            .literal = "5",
                                            .line = 1,
                                            .column = 10,
                                        },
                                        .value = 5,
                                    }
                                }
                            }
                        },
                        .consequence = ast.Block{
                            .token = Token{
                                .type = TokenType.LBRACE,
                                .literal = "{",
                                .line = 1,
                                .column = 13,
                            },
                            .statements = &[_]ast.Statement{
                                 ast.Statement{ 
                                     .returnStatement = ast.ReturnStatement{
                                         .token = Token{
                                            .type = TokenType.RETURN,
                                            .literal = "return",
                                            .line = 1,
                                            .column = 15,
                                        },
                                        .expression = &ast.Expression{
                                            .integer = ast.Integer{
                                                .token = Token{
                                                    .type = TokenType.INT,
                                                    .literal = "5",
                                                    .line = 1,
                                                    .column = 22,
                                                },
                                                .value = 5,
                                            }
                                        }
                                     }
                                 }
                            }
                        },
                        .alternative = null,
                    }
                }
            }
        },
        ast.Statement{
            .expressionStatement = ast.ExpressionStatement{
                .token = Token{
                    .type = TokenType.IF,
                    .literal = "if",
                    .line = 2,
                    .column = 1,
                },
                .expression = &ast.Expression{
                    .@"if" = ast.If{
                        .token = Token{
                            .type = TokenType.IF,
                            .literal = "if",
                            .line = 2,
                            .column = 1,
                        },
                        .condition = &ast.Expression{
                            .infix = ast.Infix{
                                .token = Token{
                                    .type = TokenType.EQUALS,
                                    .literal = "==",
                                    .line = 2,
                                    .column = 7,
                                },
                                .operator = ast.InfixOperator.EQUALS,
                                .left = &ast.Expression{
                                    .integer = ast.Integer{
                                        .token = Token{
                                            .type = TokenType.INT,
                                            .literal = "5",
                                            .line = 2,
                                            .column = 5,
                                        },
                                        .value = 5,
                                    }
                                },
                                .right = &ast.Expression{
                                    .integer = ast.Integer{
                                        .token = Token{
                                            .type = TokenType.INT,
                                            .literal = "5",
                                            .line = 2,
                                            .column = 10,
                                        },
                                        .value = 5,
                                    }
                                }
                            }
                        },
                        .consequence = ast.Block{
                            .token = Token{
                                .type = TokenType.LBRACE,
                                .literal = "{",
                                .line = 2,
                                .column = 13,
                            },
                            .statements = &[_]ast.Statement{
                                 ast.Statement{ 
                                     .returnStatement = ast.ReturnStatement{
                                         .token = Token{
                                            .type = TokenType.RETURN,
                                            .literal = "return",
                                            .line = 2,
                                            .column = 15,
                                        },
                                        .expression = &ast.Expression{
                                            .integer = ast.Integer{
                                                .token = Token{
                                                    .type = TokenType.INT,
                                                    .literal = "5",
                                                    .line = 2,
                                                    .column = 22,
                                                },
                                                .value = 5,
                                            }
                                        }
                                     }
                                 }
                            }
                        },
                        .alternative = ast.Block{
                            .token = Token{
                                .type = TokenType.LBRACE,
                                .literal = "{",
                                .line = 2,
                                .column = 32,
                            },
                            .statements = &[_]ast.Statement{
                                 ast.Statement{ 
                                     .returnStatement = ast.ReturnStatement{
                                         .token = Token{
                                            .type = TokenType.RETURN,
                                            .literal = "return",
                                            .line = 2,
                                            .column = 34,
                                        },
                                        .expression = &ast.Expression{
                                            .integer = ast.Integer{
                                                .token = Token{
                                                    .type = TokenType.INT,
                                                    .literal = "6",
                                                    .line = 2,
                                                    .column = 41,
                                                },
                                                .value = 6,
                                            }
                                        }
                                     }
                                 }
                            }
                        },
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

test "test parsing function literals" {

    const input = 
        \\let foo = fn (a, b) {
        \\    return a + b;
        \\};
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
                        .literal = "foo",
                        .line = 1,
                        .column = 5
                    },
                    .name = "foo",
                },
                .expression = &ast.Expression{
                    .function = ast.Function{
                        .token = Token{
                            .type = TokenType.FN,
                            .literal = "fn",
                            .line = 1,
                            .column = 11
                        },
                        .arguments = &[_]ast.Identifier{
                            ast.Identifier{
                                .token = Token{
                                    .type = TokenType.IDENT,
                                    .literal = "a",
                                    .line = 1,
                                    .column = 15
                                },
                                .name = "a"
                            },
                            ast.Identifier{
                                .token = Token{
                                    .type = TokenType.IDENT,
                                    .literal = "b",
                                    .line = 1,
                                    .column = 18
                                },
                                .name = "b"
                            },
                        },
                        .body = ast.Block{
                            .token = Token{
                                .type = TokenType.LBRACE,
                                .literal = "{",
                                .line = 1,
                                .column = 21
                            },
                            .statements = &[_]ast.Statement{
                                ast.Statement{
                                    .returnStatement = ast.ReturnStatement{
                                        .token = Token{
                                            .type = TokenType.RETURN,
                                            .literal = "return",
                                            .line = 2,
                                            .column = 5
                                        },
                                        .expression = &ast.Expression{
                                            .infix = ast.Infix{
                                                .token = Token{
                                                    .type = TokenType.PLUS,
                                                    .literal = "+",
                                                    .line = 2,
                                                    .column = 14
                                                },
                                                .operator = ast.InfixOperator.ADD,
                                                .left = &ast.Expression{
                                                    .identifier = ast.Identifier{
                                                        .token = Token{
                                                            .type = TokenType.IDENT,
                                                            .literal = "a",
                                                            .line = 2,
                                                            .column = 12
                                                        },
                                                        .name = "a"
                                                    }
                                                },
                                                .right = &ast.Expression{
                                                    .identifier = ast.Identifier{
                                                        .token = Token{
                                                            .type = TokenType.IDENT,
                                                            .literal = "b",
                                                            .line = 2,
                                                            .column = 16
                                                        },
                                                        .name = "b"
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
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
