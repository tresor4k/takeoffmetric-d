/**
 * vectors.json is written by the Go module github.com/tresor4k/takeoffmetric-go
 * (every row through ByID, the output of Search for a few queries, Sources).
 * The tests compare the whole D table to it; no value is typed by hand.
 * Compiled only by `dub test` (configuration "unittest").
 */
module takeoffmetric_test;

import std.algorithm.iteration : filter, map;
import std.algorithm.searching : count;
import std.array : array;
import std.conv : to;
import std.datetime.date : Date;
import std.json : JSONType, JSONValue, parseJSON;
import std.typecons : Nullable;
import takeoffmetric;

private:

immutable JSONValue vectors;

shared static this()
{
    vectors = cast(immutable) parseJSON(import("vectors.json"));
}

Nullable!double number(const JSONValue j)
{
    switch (j.type)
    {
    case JSONType.null_:
        return Nullable!double.init;
    case JSONType.float_:
        return Nullable!double(j.floating);
    case JSONType.integer:
        return Nullable!double(j.integer);
    case JSONType.uinteger:
        return Nullable!double(j.uinteger);
    default:
        assert(0, "not a number: " ~ j.toString);
    }
}

string[] strings(const JSONValue j)
{
    return j.array.map!(x => x.str).array;
}

Source source(const JSONValue j)
{
    return Source(j["publisher"].str, j["title"].str, j["url"].str, j["type"].str);
}

void same(T, U)(T got, U want, string what)
{
    assert(got == want, what ~ ": got " ~ got.to!string ~ ", want " ~ want.to!string);
}

unittest // counts
{
    same(vectors["dataset_version"].str, "1.2.0", "dataset_version");
    same(all().length, cast(size_t) vectors["count"].integer, "count");
    same(vectors["constants"].array.length, cast(size_t) vectors["count"].integer, "vector count");
    same(cast(size_t) all().count!(c => c.withheld), cast(size_t) vectors["withheld_count"].integer, "withheld");
}

unittest // every row matches Go
{
    const want = vectors["constants"].array;
    same(all().map!(c => c.id).array, want.map!(w => w["id"].str).array, "table order");
    foreach (w; want)
    {
        const id = w["id"].str;
        auto c = byID(id);
        assert(c !is null, id ~ ": byID returned null");
        same(c.id, id, id);
        same(c.category, w["category"].str, id ~ " category");
        same(c.materialOrItem, w["material_or_item"].str, id ~ " material_or_item");
        same(c.quantity, w["quantity"].str, id ~ " quantity");
        same(c.value, number(w["value"]), id ~ " value");
        same(c.valueText, w["value_text"].str, id ~ " value_text");
        same(c.unit, w["unit"].str, id ~ " unit");
        same(c.valueSI, number(w["value_si"]), id ~ " value_si");
        same(c.unitSI, w["unit_si"].str, id ~ " unit_si");
        same(c.condition, w["condition"].str, id ~ " condition");
        same(c.source, source(w["source"]), id ~ " source");
        same(c.dateOpened, Date.fromISOExtString(w["date_opened"].str), id ~ " date_opened");
        same((c.dateOpened - Date(1970, 1, 1)).total!"seconds", number(w["date_opened_unix"]).get.to!long,
            id ~ " date_opened_unix");
        same(c.usedByToolURL.dup, strings(w["used_by_tool_url"]), id ~ " used_by_tool_url");
        same(c.engineFile.dup, strings(w["engine_file"]), id ~ " engine_file");
        same(c.engineSymbol.dup, strings(w["engine_symbol"]), id ~ " engine_symbol");
        same(c.notes, w["notes"].str, id ~ " notes");
        same(c.withheld, w["withheld"].boolean, id ~ " withheld");
        same(c.withheldHosts.dup, strings(w["withheld_hosts"]), id ~ " withheld_hosts");
    }
}

unittest // withheld rows carry no number
{
    foreach (ref c; all())
    {
        if (c.withheld)
        {
            assert(c.value.isNull && c.valueSI.isNull && c.valueText == "", c.id);
            assert(c.withheldHosts.length > 0 && c.source.url != "", c.id);
        }
        else
            assert(!c.value.isNull && c.withheldHosts.length == 0, c.id);
    }
}

unittest // search matches Go
{
    const searches = vectors["searches"].array;
    assert(searches.filter!(s => s["ids"].array.length > 0).count >= 5);
    foreach (s; searches)
        same(search(s["query"].str).map!(c => c.id).array, strings(s["ids"]), `search "` ~ s["query"].str ~ `"`);
}

unittest // sources match Go
{
    same(sources(), vectors["sources"].array.map!(j => source(j)).array, "sources");
}

unittest // unknown id
{
    assert(byID("XXX-000") is null);
    assert(byID("") is null);
}

unittest // embedded CSV is the data file
{
    same(csv(), import("constants.csv"), "csv");
    assert(csv()[$ - 1] == '\n');
}
