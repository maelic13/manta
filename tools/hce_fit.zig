//! Versioned HCE parameter catalog, sparse-feature verifier and source writer.
//!
//! The catalog is derived from the committed Zig parameter source, while the
//! free/fixed/excluded policy is explicit here. A fitted vector is rendered
//! back into that source; the engine never reads a runtime parameter sidecar.
const std = @import("std");
const manta = @import("manta");
const fit_options = @import("hce_fit_options");

const schema = manta.eval.fit.schema_version;
const parameter_source = fit_options.parameter_source;
const max_declarations = 160;
const max_values = 2_048;

const Status = enum { free, fixed, excluded };

const Value = struct {
    start: usize,
    end: usize,
    current: i32,
};

const Declaration = struct {
    name: []const u8,
    first_value: usize,
    value_count: usize,
};

const Catalog = struct {
    declarations: [max_declarations]Declaration,
    declaration_count: usize = 0,
    values: [max_values]Value,
    value_count: usize = 0,

    fn init() Catalog {
        // SAFETY: both counts start at zero and parsing initializes each entry
        // before extending either observable prefix.
        return .{ .declarations = undefined, .values = undefined };
    }

    fn declaration(self: *const Catalog, name: []const u8) ?Declaration {
        for (self.declarations[0..self.declaration_count]) |item|
            if (std.mem.eql(u8, item.name, name)) return item;
        return null;
    }

    fn current(self: *const Catalog, group: []const u8, element: usize) !i32 {
        const item = self.declaration(group) orelse return error.UnknownParameterGroup;
        if (element >= item.value_count) return error.ParameterIndexOutOfBounds;
        return self.values[item.first_value + element].current;
    }
};

pub fn main(init: std.process.Init) !void {
    const catalog = try parseCatalog(parameter_source);
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    if (args.next()) |command| {
        if (std.mem.eql(u8, command, "--trace-fen")) {
            const fen_text = args.next() orelse return error.MissingFen;
            if (args.next() != null) return error.UnexpectedArgument;
            var root: manta.chess.position.PositionState = .{};
            const value = try manta.chess.fen.parse(fen_text, &root);
            const Buffer = manta.eval.trace.Buffer(manta.eval.hce.TraceValue, 12);
            var state: manta.eval.hce.Hce.State = .{};
            var traced = Buffer.init();
            _ = manta.eval.hce.Hce.evaluate(Buffer, &.{}, &state, &value, &traced);
            for (traced.slice()) |entry| switch (entry.value) {
                .tapered => |item| std.debug.print("{s}\t{d}\t{d}\n", .{ entry.label, item.middlegame, item.endgame }),
                .phase => |item| std.debug.print("{s}\t{d}\n", .{ entry.label, item }),
                .total => |item| std.debug.print("{s}\t{d}\n", .{ entry.label, item }),
            };
            return;
        }
        if (std.mem.eql(u8, command, "--extract-fen")) {
            const fen_text = args.next() orelse return error.MissingFen;
            const output_path = args.next() orelse return error.MissingFeaturePath;
            if (args.next() != null) return error.UnexpectedArgument;
            var root: manta.chess.position.PositionState = .{};
            const value = try manta.chess.fen.parse(fen_text, &root);
            var production_state: manta.eval.hce.Hce.State = .{};
            var disabled: manta.eval.trace.Disabled = .{};
            const production = manta.eval.hce.Hce.evaluate(
                manta.eval.trace.Disabled,
                &.{},
                &production_state,
                &value,
                &disabled,
            ).raw();
            const Candidate = manta.eval.hce.HceWith(.{ .contextual_space = true });
            var candidate_state: Candidate.State = .{};
            var recorder = manta.eval.fit.Recorder.init();
            _ = Candidate.evaluate(manta.eval.fit.Recorder, &.{}, &candidate_state, &value, &recorder);
            const sample = try sampleFromRecorder(&catalog, &value, production, &recorder);
            const data = try emitSample(init.gpa, sample, &recorder);
            defer init.gpa.free(data);
            try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = output_path, .data = data });
            return;
        }
        if (std.mem.eql(u8, command, "--compile-dataset")) {
            const input_path = args.next() orelse return error.MissingDatasetPath;
            const output_prefix = args.next() orelse return error.MissingDatasetPrefix;
            if (args.next() != null) return error.UnexpectedArgument;
            try compileDataset(init, &catalog, input_path, output_prefix);
            return;
        }
        const path = args.next() orelse return error.MissingVectorPath;
        if (args.next() != null) return error.UnexpectedArgument;
        if (std.mem.eql(u8, command, "--emit-vector")) {
            const data = try emitVector(init.gpa, &catalog);
            defer init.gpa.free(data);
            try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = data });
            return;
        }
        if (std.mem.eql(u8, command, "--verify-vector")) {
            const data = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(256 * 1024));
            defer init.gpa.free(data);
            var vector: [max_values]i32 = undefined;
            try parseVector(data, &catalog, vector[0..catalog.value_count]);
            std.debug.print("vector verification: PASS ({d} coefficients, schema {s})\n", .{
                catalog.value_count, schema,
            });
            return;
        }
        if (std.mem.eql(u8, command, "--apply-vector")) {
            const data = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(256 * 1024));
            defer init.gpa.free(data);
            var vector: [max_values]i32 = undefined;
            try parseVector(data, &catalog, vector[0..catalog.value_count]);
            const rendered = try renderSource(init.gpa, parameter_source, &catalog, vector[0..catalog.value_count]);
            defer init.gpa.free(rendered);
            try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = "src/eval/hce_params.zig", .data = rendered });
            return;
        }
        return error.UnknownCommand;
    }
    var status_counts: [3]usize = @splat(0);
    for (catalog.declarations[0..catalog.declaration_count]) |declaration| {
        for (0..declaration.value_count) |element| {
            status_counts[@intFromEnum(statusFor(declaration.name, element))] += 1;
        }
    }
    std.debug.print(
        "Manta HCE fitting schema\nschema: {s}\ngroups: {d}\ncoefficients: {d}\n" ++
            "free: {d}\nfixed: {d}\nexcluded: {d}\nshape: source arrays flattened as group[index]\n" ++
            "roundtrip: PASS\n",
        .{
            schema,
            catalog.declaration_count,
            catalog.value_count,
            status_counts[@intFromEnum(Status.free)],
            status_counts[@intFromEnum(Status.fixed)],
            status_counts[@intFromEnum(Status.excluded)],
        },
    );
}

const sample_record_bytes = 20;
const event_record_bytes = 8;

fn compileDataset(
    init: std.process.Init,
    catalog: *const Catalog,
    input_path: []const u8,
    output_prefix: []const u8,
) !void {
    const samples_path = try std.fmt.allocPrint(init.gpa, "{s}.samples.bin", .{output_prefix});
    defer init.gpa.free(samples_path);
    const events_path = try std.fmt.allocPrint(init.gpa, "{s}.events.bin", .{output_prefix});
    defer init.gpa.free(events_path);
    const manifest_path = try std.fmt.allocPrint(init.gpa, "{s}.manifest", .{output_prefix});
    defer init.gpa.free(manifest_path);
    const samples_tmp = try std.fmt.allocPrint(init.gpa, "{s}.tmp", .{samples_path});
    defer init.gpa.free(samples_tmp);
    const events_tmp = try std.fmt.allocPrint(init.gpa, "{s}.tmp", .{events_path});
    defer init.gpa.free(events_tmp);
    const manifest_tmp = try std.fmt.allocPrint(init.gpa, "{s}.tmp", .{manifest_path});
    defer init.gpa.free(manifest_tmp);

    const cwd = std.Io.Dir.cwd();
    var input = try cwd.openFile(init.io, input_path, .{});
    defer input.close(init.io);
    // Temporary names are exclusive and only renamed after complete flushes.
    // A failed run deliberately leaves an obvious `.tmp` artifact for manual
    // inspection rather than suppressing a second filesystem cleanup error.
    var samples_file = try cwd.createFile(init.io, samples_tmp, .{ .exclusive = true });
    var samples_closed = false;
    defer if (!samples_closed) samples_file.close(init.io);
    var events_file = try cwd.createFile(init.io, events_tmp, .{ .exclusive = true });
    var events_closed = false;
    defer if (!events_closed) events_file.close(init.io);

    var input_buffer: [4096]u8 = undefined;
    var samples_buffer: [64 * 1024]u8 = undefined;
    var events_buffer: [64 * 1024]u8 = undefined;
    var input_reader = input.readerStreaming(init.io, &input_buffer);
    var samples_writer = samples_file.writerStreaming(init.io, &samples_buffer);
    var events_writer = events_file.writerStreaming(init.io, &events_buffer);
    const reader = &input_reader.interface;
    const sample_output = &samples_writer.interface;
    const event_output = &events_writer.interface;

    const Candidate = manta.eval.hce.HceWith(.{ .contextual_space = true });
    var production_state: manta.eval.hce.Hce.State = .{};
    var candidate_state: Candidate.State = .{};
    var samples: u64 = 0;
    var events: u64 = 0;
    var rejected: u64 = 0;
    while (true) {
        const raw = reader.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => return error.DatasetLineTooLong,
            error.ReadFailed => return error.DatasetReadFailed,
        };
        const raw_line = raw orelse break;
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        const separator = std.mem.lastIndexOfScalar(u8, line, ';') orelse {
            rejected += 1;
            continue;
        };
        const target = std.fmt.parseFloat(f32, line[separator + 1 ..]) catch {
            rejected += 1;
            continue;
        };
        if (!std.math.isFinite(target) or target < 0 or target > 1) {
            rejected += 1;
            continue;
        }
        var root: manta.chess.position.PositionState = .{};
        const value = manta.chess.fen.parse(line[0..separator], &root) catch {
            rejected += 1;
            continue;
        };
        var disabled: manta.eval.trace.Disabled = .{};
        const production = manta.eval.hce.Hce.evaluate(
            manta.eval.trace.Disabled,
            &.{},
            &production_state,
            &value,
            &disabled,
        ).raw();
        var recorder = manta.eval.fit.Recorder.init();
        _ = Candidate.evaluate(manta.eval.fit.Recorder, &.{}, &candidate_state, &value, &recorder);
        if (recorder.overflowed) return error.SparseFeatureOverflow;
        const phase_value = recorder.phase orelse return error.MissingPhase;
        const start_event = events;
        for (recorder.slice()) |entry| {
            const index = try catalogIndex(catalog, entry.group, entry.element);
            if (statusFor(entry.group, entry.element) != .free) continue;
            const coefficient = eventCoefficient(entry, phase_value, value.side_to_move);
            if (coefficient == 0) continue;
            var event_record: [event_record_bytes]u8 = @splat(0);
            std.mem.writeInt(u16, event_record[0..2], @intCast(index), .little);
            std.mem.writeInt(u32, event_record[4..8], @bitCast(coefficient), .little);
            try event_output.writeAll(&event_record);
            events += 1;
        }
        const event_count = events - start_event;
        if (event_count > std.math.maxInt(u16)) return error.TooManySampleEvents;
        const white_score: f32 = @floatFromInt(if (value.side_to_move == .white) production else -production);
        var sample_record: [sample_record_bytes]u8 = @splat(0);
        std.mem.writeInt(u64, sample_record[0..8], start_event, .little);
        std.mem.writeInt(u32, sample_record[8..12], @bitCast(white_score), .little);
        std.mem.writeInt(u32, sample_record[12..16], @bitCast(target), .little);
        std.mem.writeInt(u16, sample_record[16..18], @intCast(event_count), .little);
        sample_record[18] = phase_value;
        try sample_output.writeAll(&sample_record);
        samples += 1;
    }
    try sample_output.flush();
    try event_output.flush();
    samples_file.close(init.io);
    samples_closed = true;
    events_file.close(init.io);
    events_closed = true;

    if (samples == 0) return error.EmptyDataset;
    if (rejected * 100 > samples) return error.TooManyRejectedDatasetRows;
    var manifest_buffer: [1024]u8 = undefined;
    const manifest = try std.fmt.bufPrint(
        &manifest_buffer,
        "schema\t{s}\ndataset\tmanta-hce-sparse-v1\nsamples\t{d}\nevents\t{d}\n" ++
            "coefficients\t{d}\nsample_record_bytes\t{d}\nevent_record_bytes\t{d}\nrejected\t{d}\n",
        .{ schema, samples, events, catalog.value_count, sample_record_bytes, event_record_bytes, rejected },
    );
    try cwd.writeFile(init.io, .{ .sub_path = manifest_tmp, .data = manifest });
    try std.Io.Dir.rename(cwd, samples_tmp, cwd, samples_path, init.io);
    try std.Io.Dir.rename(cwd, events_tmp, cwd, events_path, init.io);
    try std.Io.Dir.rename(cwd, manifest_tmp, cwd, manifest_path, init.io);
    std.debug.print("compiled {d} samples / {d} sparse events ({d} rejected) -> {s}\n", .{
        samples, events, rejected, output_prefix,
    });
}

fn catalogIndex(catalog: *const Catalog, group: []const u8, element: usize) !usize {
    const declaration = catalog.declaration(group) orelse return error.UnknownParameterGroup;
    if (element >= declaration.value_count) return error.ParameterIndexOutOfBounds;
    return declaration.first_value + element;
}

fn eventCoefficient(entry: manta.eval.fit.Entry, phase_value: u8, side_to_move: manta.chess.types.Color) f32 {
    const count: f32 = @floatFromInt(entry.count);
    if (entry.component == .final)
        return if (side_to_move == .white) count else -count;
    return switch (entry.lane) {
        .scalar => count,
        .middlegame => count * @as(f32, @floatFromInt(phase_value)) / 24.0,
        .endgame => count * @as(f32, @floatFromInt(24 - phase_value)) / 24.0,
    };
}

fn emitSample(
    allocator: std.mem.Allocator,
    sample: Sample,
    recorder: *const manta.eval.fit.Recorder,
) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var header_buffer: [192]u8 = undefined;
    const header = try std.fmt.bufPrint(
        &header_buffer,
        "{s}\nproduction\t{d}\nlinear\t{d}\nfixed_residual\t{d}\n",
        .{ schema, sample.production_score, sample.linear_score, sample.fixed_residual },
    );
    try output.appendSlice(allocator, header);
    for (recorder.slice()) |entry| {
        if (entry.count == 0) continue;
        var buffer: [192]u8 = undefined;
        const line = try std.fmt.bufPrint(
            &buffer,
            "{s}[{d}]\t{s}\t{s}\t{d}\n",
            .{ entry.group, entry.element, @tagName(entry.component), @tagName(entry.lane), entry.count },
        );
        try output.appendSlice(allocator, line);
    }
    return output.toOwnedSlice(allocator);
}

fn emitVector(allocator: std.mem.Allocator, catalog: *const Catalog) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    try output.appendSlice(allocator, schema ++ "\n");
    for (catalog.declarations[0..catalog.declaration_count]) |declaration| {
        for (0..declaration.value_count) |element| {
            var buffer: [160]u8 = undefined;
            const line = try std.fmt.bufPrint(
                &buffer,
                "{s}[{d}]\t{d}\t{s}\t{s}\n",
                .{
                    declaration.name,
                    element,
                    catalog.values[declaration.first_value + element].current,
                    @tagName(statusFor(declaration.name, element)),
                    unitFor(declaration.name),
                },
            );
            try output.appendSlice(allocator, line);
        }
    }
    return output.toOwnedSlice(allocator);
}

fn parseVector(data: []const u8, catalog: *const Catalog, vector: []i32) !void {
    var lines = std.mem.splitScalar(u8, data, '\n');
    if (!std.mem.eql(u8, lines.next() orelse return error.EmptyVector, schema)) return error.SchemaMismatch;
    var flat_index: usize = 0;
    for (catalog.declarations[0..catalog.declaration_count]) |declaration| {
        for (0..declaration.value_count) |element| {
            const line = lines.next() orelse return error.ShortVector;
            var fields = std.mem.splitScalar(u8, line, '\t');
            const name = fields.next() orelse return error.InvalidVector;
            const value_text = fields.next() orelse return error.InvalidVector;
            const status_text = fields.next() orelse return error.InvalidVector;
            const unit_text = fields.next() orelse return error.InvalidVector;
            var expected_buffer: [128]u8 = undefined;
            const expected_name = try std.fmt.bufPrint(&expected_buffer, "{s}[{d}]", .{ declaration.name, element });
            if (!std.mem.eql(u8, name, expected_name)) return error.ParameterOrderMismatch;
            if (!std.mem.eql(u8, status_text, @tagName(statusFor(declaration.name, element))))
                return error.ParameterStatusMismatch;
            if (!std.mem.eql(u8, unit_text, unitFor(declaration.name))) return error.ParameterUnitMismatch;
            const parsed = try std.fmt.parseInt(i32, value_text, 10);
            const source_value = catalog.values[flat_index].current;
            const status = statusFor(declaration.name, element);
            if (status != .free and parsed != source_value)
                return error.NonFreeParameterChanged;
            if (status == .free and (parsed < std.math.minInt(i16) or parsed > std.math.maxInt(i16)))
                return error.FreeParameterOutOfRange;
            vector[flat_index] = parsed;
            flat_index += 1;
        }
    }
    while (lines.next()) |line| if (line.len != 0) return error.LongVector;
}

fn parseCatalog(source: []const u8) !Catalog {
    var result = Catalog.init();
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, source, cursor, "pub const ")) |start| {
        const name_start = start + "pub const ".len;
        var name_end = name_start;
        while (name_end < source.len and isName(source[name_end])) : (name_end += 1) {}
        const equals = std.mem.indexOfPos(u8, source, name_end, "=") orelse return error.InvalidParameterSource;
        const semicolon = std.mem.indexOfPos(u8, source, equals, ";") orelse return error.InvalidParameterSource;
        if (result.declaration_count == result.declarations.len) return error.TooManyParameterGroups;
        const first_value = result.value_count;
        try scanValues(source, equals + 1, semicolon, &result);
        if (result.value_count == first_value) return error.ParameterWithoutValue;
        result.declarations[result.declaration_count] = .{
            .name = source[name_start..name_end],
            .first_value = first_value,
            .value_count = result.value_count - first_value,
        };
        result.declaration_count += 1;
        cursor = semicolon + 1;
    }
    return result;
}

fn scanValues(source: []const u8, start: usize, end: usize, catalog: *Catalog) !void {
    // Inferred array declarations begin with a typed literal such as
    // `[2][2]i16{...}`. Its dimensions describe shape and are not coefficients.
    const brace = std.mem.indexOfPos(u8, source, start, "{");
    var cursor = if (brace != null and brace.? < end) brace.? + 1 else start;
    while (cursor < end) {
        if (cursor + 1 < end and source[cursor] == '/' and source[cursor + 1] == '/') {
            cursor = std.mem.indexOfPos(u8, source, cursor, "\n") orelse end;
            continue;
        }
        const negative = source[cursor] == '-' and cursor + 1 < end and std.ascii.isDigit(source[cursor + 1]);
        if (!std.ascii.isDigit(source[cursor]) and !negative) {
            cursor += 1;
            continue;
        }
        const token_start = cursor;
        if (negative) cursor += 1;
        const digits_start = cursor;
        while (cursor < end and (std.ascii.isDigit(source[cursor]) or source[cursor] == '_')) : (cursor += 1) {}
        if (catalog.value_count == catalog.values.len) return error.TooManyParameters;
        var compact: [32]u8 = undefined;
        var compact_len: usize = 0;
        for (source[digits_start..cursor]) |byte| {
            if (byte == '_') continue;
            compact[compact_len] = byte;
            compact_len += 1;
        }
        const magnitude = try std.fmt.parseInt(i32, compact[0..compact_len], 10);
        catalog.values[catalog.value_count] = .{
            .start = token_start,
            .end = cursor,
            .current = if (negative) -magnitude else magnitude,
        };
        catalog.value_count += 1;
    }
}

fn isName(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

fn statusFor(name: []const u8, element: usize) Status {
    if (std.mem.startsWith(u8, name, "endgame_")) return .excluded;
    if ((std.mem.eql(u8, name, "mg_val") or std.mem.eql(u8, name, "eg_val")) and
        (element == 0 or element == 6)) return .fixed;
    const fixed = [_][]const u8{
        "phase_weight", "phase_total", "trapped_rook_mobility", "winnability_max_bonus",
        "scale_normal", "scale_draw",  "king_danger_divisor",
    };
    for (fixed) |item| if (std.mem.eql(u8, name, item)) return .fixed;
    const excluded = [_][]const u8{
        "connected",                  "connected_mg",                  "connected_eg",
        "king_attack_weight",         "safe_check_weight",             "unsafe_check_weight",
        "king_ring_weak",             "king_blocker_danger",           "king_flank_attack_danger",
        "king_flank_defense_danger",  "king_pawn_attack_weight",       "king_no_queen_relief",
        "king_defender_queen_relief", "winnability_base",              "winnability_passed",
        "winnability_pawn_count",     "winnability_pawn_ending",       "winnability_outflanking",
        "winnability_both_flanks",    "winnability_infiltration",      "winnability_almost_unwinnable",
        "scale_opposite_bishops",     "scale_opposite_bishops_pieces", "scale_wrong_rook_pawn",
        "scale_no_pawns_minor",       "scale_pawnful_base",            "scale_per_pawn",
    };
    for (excluded) |item| if (std.mem.eql(u8, name, item)) return .excluded;
    return .free;
}

fn unitFor(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "phase_weight") or std.mem.eql(u8, name, "phase_total"))
        return "phase";
    if (std.mem.eql(u8, name, "trapped_rook_mobility")) return "count";
    if (std.mem.startsWith(u8, name, "scale_") or
        std.mem.eql(u8, name, "endgame_kbpkb") or
        std.mem.eql(u8, name, "endgame_kbpkn") or
        std.mem.eql(u8, name, "endgame_kbppkb") or
        std.mem.eql(u8, name, "endgame_kpkp") or
        std.mem.eql(u8, name, "endgame_krpkb") or
        std.mem.eql(u8, name, "endgame_krpkr") or
        std.mem.eql(u8, name, "endgame_krppkrp")) return "factor/64";
    if (std.mem.eql(u8, name, "king_danger_divisor")) return "cp-divisor";
    return "cp";
}

fn renderSource(allocator: std.mem.Allocator, source: []const u8, catalog: *const Catalog, vector: []const i32) ![]u8 {
    if (vector.len != catalog.value_count) return error.ParameterCountMismatch;
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var cursor: usize = 0;
    for (catalog.values[0..catalog.value_count], vector) |current, replacement| {
        try output.appendSlice(allocator, source[cursor..current.start]);
        if (replacement == current.current) {
            try output.appendSlice(allocator, source[current.start..current.end]);
        } else {
            var buffer: [32]u8 = undefined;
            const text = try std.fmt.bufPrint(&buffer, "{d}", .{replacement});
            try output.appendSlice(allocator, text);
        }
        cursor = current.end;
    }
    try output.appendSlice(allocator, source[cursor..]);
    return output.toOwnedSlice(allocator);
}

const Tapered64 = struct { middlegame: i64 = 0, endgame: i64 = 0 };

fn sparseDot(catalog: *const Catalog, recorder: *const manta.eval.fit.Recorder) ![9]Tapered64 {
    var totals: [9]Tapered64 = @splat(.{});
    for (recorder.slice()) |entry| {
        if (statusFor(entry.group, entry.element) != .free) continue;
        const contribution = @as(i64, try catalog.current(entry.group, entry.element)) * entry.count;
        const target = &totals[@intFromEnum(entry.component)];
        switch (entry.lane) {
            .middlegame => target.middlegame += contribution,
            .endgame => target.endgame += contribution,
            .scalar => {
                target.middlegame += contribution;
                target.endgame += contribution;
            },
        }
    }
    return totals;
}

const Sample = struct {
    linear_score: i32,
    fixed_residual: i32,
    production_score: i32,

    fn reconstruct(self: Sample) i32 {
        return self.linear_score + self.fixed_residual;
    }
};

fn extractSample(catalog: *const Catalog, value: *const manta.chess.position.Position) !Sample {
    var state: manta.eval.hce.Hce.State = .{};
    var recorder = manta.eval.fit.Recorder.init();
    const production = manta.eval.hce.Hce.evaluate(
        manta.eval.fit.Recorder,
        &.{},
        &state,
        value,
        &recorder,
    ).raw();
    if (recorder.total != production) return error.TraceScoreMismatch;
    return sampleFromRecorder(catalog, value, production, &recorder);
}

fn sampleFromRecorder(
    catalog: *const Catalog,
    value: *const manta.chess.position.Position,
    production: i32,
    recorder: *const manta.eval.fit.Recorder,
) !Sample {
    if (recorder.overflowed) return error.SparseFeatureOverflow;
    const phase_value = recorder.phase orelse return error.MissingPhase;
    _ = recorder.total orelse return error.MissingTotal;
    const dots = try sparseDot(catalog, recorder);
    var tapered: Tapered64 = .{};
    for (dots[0..@intFromEnum(manta.eval.fit.Component.final)]) |item| {
        tapered.middlegame += item.middlegame;
        tapered.endgame += item.endgame;
    }
    const weighted = tapered.middlegame * phase_value + tapered.endgame * (24 - phase_value);
    const white_linear: i32 = @intCast(@divTrunc(weighted, 24));
    const tempo = dots[@intFromEnum(manta.eval.fit.Component.final)].middlegame;
    const linear: i32 = (if (value.side_to_move == .white) white_linear else -white_linear) + @as(i32, @intCast(tempo));
    return .{
        .linear_score = linear,
        .fixed_residual = production - linear,
        .production_score = production,
    };
}

fn expectExactComponents(catalog: *const Catalog, value: *const manta.chess.position.Position) !void {
    const TraceBuffer = manta.eval.trace.Buffer(manta.eval.hce.TraceValue, 16);
    var feature_state: manta.eval.hce.Hce.State = .{};
    var recorder = manta.eval.fit.Recorder.init();
    _ = manta.eval.hce.Hce.evaluate(manta.eval.fit.Recorder, &.{}, &feature_state, value, &recorder);
    const dots = try sparseDot(catalog, &recorder);

    var trace_state: manta.eval.hce.Hce.State = .{};
    var trace = TraceBuffer.init();
    _ = manta.eval.hce.Hce.evaluate(TraceBuffer, &.{}, &trace_state, value, &trace);
    const exact = [_]manta.eval.fit.Component{
        .material_pst, .activity, .passed, .pawn_threats, .threats_space,
    };
    for (exact) |component| {
        try expectComponentDot(component, dots, trace.slice());
    }
}

fn expectComponentDot(
    component: manta.eval.fit.Component,
    dots: [9]Tapered64,
    trace: anytype,
) !void {
    const label = @tagName(component);
    for (trace) |entry| {
        if (!std.mem.eql(u8, entry.label, label)) continue;
        const dot = dots[@intFromEnum(component)];
        try std.testing.expectEqual(@as(i64, entry.value.tapered.middlegame), dot.middlegame);
        try std.testing.expectEqual(@as(i64, entry.value.tapered.endgame), dot.endgame);
        return;
    }
    return error.MissingTraceComponent;
}

test "parameter schema covers source and round-trips byte exactly" {
    const catalog = try parseCatalog(parameter_source);
    try std.testing.expectEqual(@as(usize, 125), catalog.declaration_count);
    try std.testing.expectEqual(@as(usize, 1_229), catalog.value_count);
    var current: [max_values]i32 = undefined;
    for (catalog.values[0..catalog.value_count], 0..) |value, index| current[index] = value.current;
    const rendered = try renderSource(std.testing.allocator, parameter_source, &catalog, current[0..catalog.value_count]);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(parameter_source, rendered);

    var free_count: usize = 0;
    for (catalog.declarations[0..catalog.declaration_count]) |declaration| {
        for (0..declaration.value_count) |element| {
            if (statusFor(declaration.name, element) == .free) free_count += 1;
        }
    }
    try std.testing.expect(free_count > 800);

    const emitted = try emitVector(std.testing.allocator, &catalog);
    defer std.testing.allocator.free(emitted);
    var parsed: [max_values]i32 = undefined;
    try parseVector(emitted, &catalog, parsed[0..catalog.value_count]);
    try std.testing.expectEqualSlices(i32, current[0..catalog.value_count], parsed[0..catalog.value_count]);

    const mg = catalog.declaration("mg_val").?;
    parsed[mg.first_value + 1] += 1;
    const changed = try renderSource(std.testing.allocator, parameter_source, &catalog, parsed[0..catalog.value_count]);
    defer std.testing.allocator.free(changed);
    const changed_catalog = try parseCatalog(changed);
    try std.testing.expectEqual(parsed[mg.first_value + 1], try changed_catalog.current("mg_val", 1));
}

test "binary switches are absent from the coefficient schema" {
    const catalog = try parseCatalog(parameter_source);
    const switches = [_][]const u8{
        "pawn_completion",   "pawn_cache",  "piece_detail",     "threat_completion",
        "endgame_knowledge", "winnability", "contextual_space", "endgame_scaling",
    };
    for (switches) |name| try std.testing.expect(catalog.declaration(name) == null);
}

test "final-repair parameters have honest fitting authority" {
    const free = [_][]const u8{
        "candidate_mg",
        "candidate_eg",
        "passed_path_attacked",
        "passed_path_defended",
        "shelter_rank",
        "king_pawn_proximity",
    };
    for (free) |name| try std.testing.expectEqual(Status.free, statusFor(name, 0));

    const nonlinear = [_][]const u8{
        "king_pawn_attack_weight",
        "king_no_queen_relief",
        "king_defender_queen_relief",
        "endgame_tempo",
        "endgame_king_geometry",
        "winnability_pawn_count",
        "winnability_pawn_ending",
    };
    for (nonlinear) |name| try std.testing.expectEqual(Status.excluded, statusFor(name, 0));
}

test "compiled sparse coefficients preserve white POV and tapered phase" {
    const base = manta.eval.fit.Entry{
        .group = "test",
        .element = 0,
        .component = .pawns,
        .lane = .middlegame,
        .count = 24,
    };
    try std.testing.expectEqual(@as(f32, 12), eventCoefficient(base, 12, .white));
    var endgame = base;
    endgame.lane = .endgame;
    try std.testing.expectEqual(@as(f32, 12), eventCoefficient(endgame, 12, .black));
    var final = base;
    final.component = .final;
    final.lane = .scalar;
    final.count = 3;
    try std.testing.expectEqual(@as(f32, 3), eventCoefficient(final, 12, .white));
    try std.testing.expectEqual(@as(f32, -3), eventCoefficient(final, 12, .black));
}

test "sparse features reproduce production on conformance positions" {
    const catalog = try parseCatalog(parameter_source);
    for (manta.eval.cohorts.cases) |case| {
        var root: manta.chess.position.PositionState = .{};
        const value = try manta.chess.fen.parse(case.fen, &root);
        const sample = try extractSample(&catalog, &value);
        try std.testing.expectEqual(sample.production_score, sample.reconstruct());
        try expectExactComponents(&catalog, &value);
    }
}

test "pawn and quiet-king free surfaces have no hidden residual" {
    const catalog = try parseCatalog(parameter_source);
    var root: manta.chess.position.PositionState = .{};
    const value = try manta.chess.fen.parse("4k3/p7/p7/8/8/7P/7P/4K3 w - - 0 1", &root);
    const TraceBuffer = manta.eval.trace.Buffer(manta.eval.hce.TraceValue, 16);
    var feature_state: manta.eval.hce.Hce.State = .{};
    var recorder = manta.eval.fit.Recorder.init();
    _ = manta.eval.hce.Hce.evaluate(manta.eval.fit.Recorder, &.{}, &feature_state, &value, &recorder);
    const dots = try sparseDot(&catalog, &recorder);
    var trace_state: manta.eval.hce.Hce.State = .{};
    var trace = TraceBuffer.init();
    _ = manta.eval.hce.Hce.evaluate(TraceBuffer, &.{}, &trace_state, &value, &trace);
    try expectComponentDot(.pawns, dots, trace.slice());
    try expectComponentDot(.king_safety, dots, trace.slice());
}

test "prospective contextual space uses the sole free space coordinate" {
    const catalog = try parseCatalog(parameter_source);
    var root: manta.chess.position.PositionState = .{};
    const value = try manta.chess.fen.parse(
        "4k3/8/8/8/8/8/8/RNBQKBNR w KQ - 0 1",
        &root,
    );
    const Candidate = manta.eval.hce.HceWith(.{ .contextual_space = true });
    var state: Candidate.State = .{};
    var recorder = manta.eval.fit.Recorder.init();
    _ = Candidate.evaluate(manta.eval.fit.Recorder, &.{}, &state, &value, &recorder);
    var found = false;
    for (recorder.slice()) |entry| {
        if (!std.mem.eql(u8, entry.group, "space_bonus") or entry.count == 0) continue;
        try std.testing.expectEqual(manta.eval.fit.Component.threats_space, entry.component);
        try std.testing.expectEqual(manta.eval.fit.Lane.middlegame, entry.lane);
        try std.testing.expectEqual(Status.free, statusFor(entry.group, entry.element));
        found = true;
    }
    try std.testing.expect(found);
    try std.testing.expect(catalog.declaration("contextual_space") == null);
}

test "sparse features reproduce production on deterministic random legal positions" {
    const catalog = try parseCatalog(parameter_source);
    var root: manta.chess.position.PositionState = .{};
    var value = try manta.chess.fen.parseStart(&root);
    var states: [96]manta.chess.position.PositionState = undefined;
    var random: u64 = 0x6d61_6e74_612d_3533;
    for (&states) |*child| {
        const sample = try extractSample(&catalog, &value);
        try std.testing.expectEqual(sample.production_score, sample.reconstruct());
        try expectExactComponents(&catalog, &value);
        var legal = manta.chess.position.MoveList.init();
        manta.chess.movegen.generate(.all, &value, &legal);
        if (legal.count == 0) break;
        random = random *% 6_364_136_223_846_793_005 +% 1_442_695_040_888_963_407;
        const selected = legal.slice()[@as(usize, @intCast(random % legal.count))];
        manta.chess.transition.makeMove(&value, selected, child);
    }
}
