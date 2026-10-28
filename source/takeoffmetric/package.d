/**
 * TakeoffMetric US construction estimating constants, dataset version 1.2.0.
 *
 * A port of the Go module github.com/tresor4k/takeoffmetric-go: the same table
 * (data/constants.csv), embedded at compile time as typed, read-only records.
 * Lookup only: the package computes nothing. Method:
 * https://takeoffmetric.com/methodology/
 *
 * Estimating values only: confirm with your plans, your supplier and your local
 * code before ordering or building.
 *
 * License: code MIT; embedded data (`data/`) see data/LICENSE.
 */
module takeoffmetric;

import std.algorithm.iteration : filter, map;
import std.algorithm.searching : allOf = all, canFind;
import std.algorithm.sorting : sort;
import std.array : array, join, split;
import std.conv : to;
import std.csv : csvReader;
import std.datetime.date : Date;
import std.exception : assumeUnique, enforce;
import std.typecons : Nullable;
import std.uni : toLower;

/// The publication a constant was read in.
struct Source
{
    string publisher;
    string title;
    string url;
    /// federal_public_domain, manufacturer_datasheet, trade_association, supplier or other.
    string type;
}

/**
 * One row of the constants table. `value` and `valueSI` are the numbers of the
 * row; `valueText` keeps the value as the source prints it.
 *
 * When `withheld` is true the publisher does not allow republication: `value`
 * and `valueSI` are null, `valueText` is empty, and the value is read at
 * `source.url`.
 */
struct Constant
{
    /// Stable row id, for example "CON-001".
    string id;
    /// concrete, rebar, aggregates, earthwork, ...
    string category;
    /// The product or material the value is for.
    string materialOrItem;
    /// What the value measures.
    string quantity;
    /// The value in US customary units; null when `withheld`.
    Nullable!double value;
    /// `value` exactly as written in the table.
    string valueText;
    /// Unit of `value`.
    string unit;
    /// SI conversion of `value`; null when `withheld` or when the table leaves it empty.
    Nullable!double valueSI;
    /// Unit of `valueSI`.
    string unitSI;
    /// The condition the value applies to (loose, bank, compacted, ...).
    string condition;
    /// The publication the value was read in.
    Source source;
    /// Date the source was opened and the value read.
    Date dateOpened;
    /// TakeoffMetric calculator pages that use the value.
    string[] usedByToolURL;
    /// Site source files holding the value (not part of this package).
    string[] engineFile;
    /// Symbols in those files, one per `engineFile` entry.
    string[] engineSymbol;
    string notes;
    /// True when the publisher does not allow republication of the value.
    bool withheld;
    /// Domains of the publishers concerned, set only when `withheld`.
    string[] withheldHosts;
}

/// Every constant, in table order.
immutable(Constant)[] all() @safe nothrow @nogc
{
    return table;
}

/// The constant with the given id, for example "CON-001", or null.
immutable(Constant)* byID(string id) @safe nothrow
{
    if (auto i = id in index)
        return &table[*i];
    return null;
}

/**
 * The constants whose id, category, material, quantity, condition, publisher
 * or notes contain every word of `query`, ignoring case. An empty query
 * returns nothing.
 */
immutable(Constant)[] search(string query) @safe
{
    auto words = query.toLower.split;
    if (words.length == 0)
        return [];
    return table.filter!((ref c) {
        const text = [c.id, c.category, c.materialOrItem, c.quantity, c.condition,
            c.source.publisher, c.notes].join(" ").toLower;
        return words.allOf!(w => text.canFind(w));
    }).array;
}

/**
 * Each distinct source of the table once, sorted by publisher, then title,
 * then URL (byte order, as in the Go module).
 */
Source[] sources() @safe
{
    bool[Source] seen;
    Source[] output;
    foreach (ref c; table)
    {
        Source s = c.source;
        if (s in seen)
            continue;
        seen[s] = true;
        output ~= s;
    }
    output.sort!((a, b) => a.publisher != b.publisher ? a.publisher < b.publisher
            : a.title != b.title ? a.title < b.title : a.url < b.url);
    return output;
}

/**
 * The embedded table as published (UTF-8, comma-separated). Withheld rows
 * carry no value in it either. See `Constant` and data/LICENSE for the
 * licence of each part.
 */
string csv() @safe pure nothrow @nogc
{
    return constantsCsv;
}

private:

immutable constantsCsv = import("constants.csv");
immutable Constant[] table;
immutable size_t[string] index;

enum header = "id,category,material_or_item,quantity,value,unit,value_si,unit_si,condition,"
    ~ "source_publisher,source_title,source_url,source_type,date_opened,used_by_tool_url,"
    ~ "engine_file,engine_symbol,notes,values_withheld,withheld_hosts";

shared static this()
{
    Constant[] rows;
    size_t[string] ids;
    size_t line = 1;
    foreach (r; csvReader!string(constantsCsv))
    {
        auto f = r.array;
        if (line == 1)
            enforce(f.join(",") == header, "data/constants.csv: unexpected header");
        else
        {
            try
                rows ~= parse(f);
            catch (Exception e)
                throw new Exception("data/constants.csv row " ~ line.to!string ~ ": " ~ e.msg);
            ids[rows[$ - 1].id] = rows.length - 1;
        }
        line++;
    }
    table = assumeUnique(rows);
    index = assumeUnique(ids);
}

Constant parse(string[] r)
{
    enforce(r.length == 20, r.length.to!string ~ " fields, want 20");
    Constant c;
    switch (r[18])
    {
    case "true":
        c.withheld = true;
        // A withheld row must carry no number at all.
        enforce(r[4] == "" && r[6] == "", "withheld row has a value");
        break;
    case "false":
        enforce(r[19] == "", "withheld_hosts set on a row that is not withheld");
        c.value = r[4].to!double;
        break;
    default:
        throw new Exception(`values_withheld: "` ~ r[18] ~ `", want true or false`);
    }
    if (r[6] != "")
        c.valueSI = r[6].to!double;
    c.id = r[0];
    c.category = r[1];
    c.materialOrItem = r[2];
    c.quantity = r[3];
    c.valueText = r[4];
    c.unit = r[5];
    c.unitSI = r[7];
    c.condition = r[8];
    c.source = Source(r[9], r[10], r[11], r[12]);
    c.dateOpened = Date.fromISOExtString(r[13]);
    c.usedByToolURL = splitList(r[14], "; ");
    c.engineFile = splitList(r[15], "; ");
    c.engineSymbol = splitList(r[16], "; ");
    c.notes = r[17];
    c.withheldHosts = splitList(r[19], ";");
    return c;
}

string[] splitList(string s, string separator)
{
    return s == "" ? [] : s.split(separator);
}
