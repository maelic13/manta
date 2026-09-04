# ADR-0013: Board representation and immutable attack geometry

- Status: Accepted
- Date: 2026-08-07

## Context

The chess core needs constant-time piece lookup, fast set operations, compact
per-ply state and exact x86-64/ARM64 behavior. It must also support reversible
state, later incremental evaluators and measured ISA specialization without
runtime initialization or a generic abstraction in node paths.

## Decision

Use `a1 = 0` little-endian rank-file squares and a deliberately redundant
physical position:

- a 64-entry piece mailbox;
- one bitboard per piece type, with index zero holding total occupancy;
- one occupancy bitboard per color; and
- compact piece counts.

Moves are 16-bit values containing origin, destination, a two-bit special kind
and promotion choice. Standard castling stores the king's actual destination.
Zero is no move; a reserved same-square value is the internal null move.
Checked construction rejects invalid squares, same-square chess moves and
invalid promotion combinations.

Each position borrows a pointer to caller-owned, stable-address
`PositionState`. Search owns fixed per-ply state and move arrays; the controller
separately owns dynamically sized game history. A factual move delta holds at
most three remove/add changes, which covers promotion captures without giving
the chess layer evaluator-specific meaning. Position copies must explicitly
rebind their current-state pointer.

Only factual checkers are cached initially. Pins and other derived geometry
are recomputed until whole-search evidence justifies another cache. En-passant
state will be retained and hashed only when the side to move has a legal
en-passant capture. Harmless stale castling or en-passant FEN fields may be
normalized at the checked input boundary; malformed core fields are rejected.

Legal move generation is direct and allocation-free, specialized at compile
time by color and exact all/capture/quiet mode. Captures and quiets are a
disjoint semantic partition; search-specific tactical staging may be added at
the search boundary without changing those chess-domain meanings. A separate
full legality query accepts arbitrary encoded moves, while generated moves may
enter hot make/unmake under its documented precondition. Standard coordinate
notation uses fixed storage and resolves external text against the legal set.

Checked setup accepts exactly the six standard-chess FEN fields, constructs a
temporary candidate and commits caller state only after complete validation.
The full key covers pieces, side, castling and legal en-passant identity. The
pawn key covers pawns, the minor key covers knights and bishops, and each
per-color non-pawn key covers every non-pawn including its king. Setup rebuilds
all redundant physical facts from the mailbox rather than incrementally
mutating a previously valid position.

Knight, king, pawn, line, between and deterministic Zobrist data are compile-
time constants. Sliding attacks use checked-in, little-endian tables generated
offline from project-owned deterministic magic constants on x86-64. ARM64 uses
hyperbola quintessence with bit reversal. Both are verified exhaustively
against an independent coordinate-ray oracle. Table generation is an explicit
maintenance command and never occurs during startup or an ordinary build.
Future PEXT, vector or other backends require measurement and exact conformance;
dispatch remains a coarse architecture/backend decision rather than a branch
inside each primitive.

Only standard chess is implemented. Rule facts remain centralized so a future
variant can add a sibling rules implementation without placing variant flags
in the present hot structures.

## Consequences

- Piece-at-square and piece-set queries are both constant-time, at the cost of
  intentionally maintaining redundant facts.
- Compile-time layout budgets protect worker shape without freezing incidental
  field offsets.
- Static attack assets increase the repository and binary size but remove
  startup search, allocation and mutable initialization.
- Phase 2.1 must make every redundant fact and key transactionally consistent;
  Phase 2.2 independently recomputes them after randomized make/unmake.
- The Phase 2.3 whole-board benchmark can overturn a backend or cache choice;
  it does not silently change the semantic representation contract.

## Verification

- Compile-time size/alignment and encoding assertions cover the hot values.
- Unit tests cover coordinate, piece, move, pointer/rebind and delta invariants.
- Every relevant blocker subset for every sliding square is compared with an
  independently expressed oracle for both retained algorithms.
- Zobrist generation is deterministic, nonzero for legal facts and free of
  runtime state.
- Debug, ReleaseSafe and ReleaseFast tests plus native CI cover the supported
  architecture matrix.

## Traceability

Selects the choices deferred by ADR-0003 and supports `FUNC-001`, `FUNC-002`,
`SCORE-003`, `RES-004`, `PERF-001` and Phase 2 Steps 2.0-2.3.
