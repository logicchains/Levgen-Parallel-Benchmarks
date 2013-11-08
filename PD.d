// Compile with:
// ldc2 -O5 -check-printf-calls -fdata-sections -ffunction-sections -release -singleobj -strip-debug -wi -disable-boundscheck -L=--gc-sections -L=-s PD.d

import std.conv, std.stdio, std.parallelism;

@safe:

enum levelSize = 50;   /// Width and height of a level.
enum nRooms = 100;     /// Maximum number of rooms in a level.
enum roomSizeBase = 2; /// Rooms will be at least this value plus one in size.
enum roomSizeMod = 8;  /// Random additional room size: [0 .. roomSizeMod).

enum nLevels = 800;
enum nTries = 50_000;

struct Tile { uint x, y, t; }

struct Room {
    uint x, y, w, h;
    size_t number;
}

struct Level {
    Tile[levelSize ^^ 2] tiles = void;
    Room[nRooms] rooms = void;
    size_t roomCnt = 0;

    void makeRoom(ref Random rnd) nothrow {
        immutable x = rnd.next % levelSize;
        if (x == 0)
            return;
        immutable y = rnd.next % levelSize;
        if (y == 0)
            return;

        immutable w = roomSizeBase + rnd.next % roomSizeMod;
        immutable h = roomSizeBase + rnd.next % roomSizeMod;
        if (x + w >= levelSize || y + h >= levelSize)
            return;
        if (checkColl(x, y, w, h))
            return;

        this.rooms[this.roomCnt] = Room(x, y, w, h, this.roomCnt++);
    }

    /// Returns true, when the given area collides with existing rooms.
    bool checkColl(in uint x, in uint y, in uint w, in uint h) const pure nothrow {
        foreach (const ref r; this.rooms[0 .. this.roomCnt])
            if (r.x + r.w + 1 >= x && r.x <= x + w + 1 &&
                r.y + r.h + 1 >= y && r.y <= y + h + 1)
                return true;
        return false;
    }

    /// Initializes and then builds the tiles from the room definitions.
    void buildTiles() pure nothrow {
        foreach (immutable uint i, ref t; this.tiles)
            t = Tile(i % levelSize, i / levelSize, 0);

        foreach (const ref r; this.rooms[0 .. this.roomCnt])
            foreach (immutable xi; r.x .. r.x + r.w + 1)
                foreach (immutable yi; r.y .. r.y + r.h + 1)
                    this.tiles[yi * levelSize + xi].t = 1;
    }

    void dump() @system const {
        foreach (immutable row; 0 .. levelSize) {
            immutable offset = levelSize * row;
            foreach (immutable col; 0 .. levelSize)
                this.tiles[offset + col].t.write;
            writeln;
        }
    }
}

struct Random {
    uint current;

    uint next() pure nothrow {
        current += current;
        current ^= (current > int.max) ? 0x88888eee : 1;
        return current;
    }
}


void main(in string[] args) @system {
    static __gshared Level[nLevels] levels;

    // Create a local random number generator.
    immutable seed = (args.length > 1) ? args[1].to!uint : 123;
    writefln("The random seed is: %s", seed);

    // Create several levels for benchmarking purposes.
    foreach (levelIdx, ref level; levels[].parallel) {
        auto rnd = Random(cast(uint)(seed * (levelIdx + 1) * (levelIdx + 1)));
        foreach (immutable i; 0 .. nTries) {
            level.makeRoom(rnd);
            if (level.roomCnt == nRooms)
                break;
        }
        level.buildTiles;
    }

    // Select the level with the most rooms for printing.
    auto levelToPrint = &levels[0];
    foreach (ref level; levels[1 .. $])
        if (level.roomCnt > levelToPrint.roomCnt)
            levelToPrint = &level;
    levelToPrint.dump;
}
