# AGENTS.md

## Commands
- `zig build` — build the `monkey` binary
- `zig build run` — launch REPL
- `zig build run -- <file>` — evaluate a Monkey source file
- `zig build test` — run all tests (module tests + exe tests in parallel)
- `zig test src/<file>.zig` — run tests from a single implementation file

## Architecture
Standard interpreter pipeline: `Scanner → Parser → AST → Evaluator`
- `src/root.zig` re-exports all modules (public API)
- `src/main.zig` — CLI entrypoint (optional filename arg → evaluateFile, else REPL)
- `src/repl.zig` — REPL loop + file evaluation, manages ArenaAllocator + DebugAllocator
- `src/scanner.zig` — hand-written character scanner
- `src/parser.zig` — Pratt parser (precedence climbing)
- `src/evaluate.zig` — tree-walking evaluator
- `src/object.zig` — runtime objects + `Environment` (lexical scoping via nested envs)
- `src/token.zig` — token types + keyword lookup map
- `src/ast.zig` — AST nodes (Statement, Expression, Program)

## Notes
- Zig 0.16.0, no external dependencies
- Tests use `std.testing.expectEqualDeep` extensively; tests are embedded in their respective implementation files
- `.gitignore` entries: `.zig-cache` and `zig-out`
- No formatter/linter/typechecker beyond `zig build` (the compiler handles type checking)
