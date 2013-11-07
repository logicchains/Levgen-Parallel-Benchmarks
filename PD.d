// Compile with:
// ldc2 -O5 -check-printf-calls -fdata-sections -ffunction-sections -release -singleobj -strip-debug -wi -disable-boundscheck -L=--gc-sections -L=-s  D.d
 
@safe:
import std.conv, std.stdio, std.parallelism;
 
enum LEVEL_SIZE     =  50;   /// Width and height of a level
enum ROOMS          = 100;   /// Maximum number of rooms in a level
enum ROOM_SIZE_BASE =   2;   /// Rooms will be at least this value plus one in size.
enum ROOM_SIZE_MOD  =   8;   /// Random additional room size: [0 .. ROOM_SIZE_MOD)
 
enum NUM_LEVS       = 800;
enum NUM_TRIES      = 50000;
 
struct Tile {
	uint x;
	uint y;
	uint t;
}
 
struct Room {
	uint   x;
	uint   y;
	uint   w;
	uint   h;
	size_t number;
}
 
struct Level {
	Tile[LEVEL_SIZE ^^ 2] tiles   = void;
	Room[ROOMS]           rooms   = void;
	size_t                roomCnt = 0;
 
	void makeRoom(ref Random rnd) nothrow {
		immutable x = rnd.next() % LEVEL_SIZE;
		immutable y = rnd.next() % LEVEL_SIZE;
		if (x == 0 || y == 0) return;
		
		immutable w = ROOM_SIZE_BASE + rnd.next() % ROOM_SIZE_MOD;
		immutable h = ROOM_SIZE_BASE + rnd.next() % ROOM_SIZE_MOD;
		if (x + w >= LEVEL_SIZE || y + h >= LEVEL_SIZE) return;
		if (checkColl( x, y, w, h )) return;
 
		Room* r = &this.rooms[this.roomCnt];
		r.number = this.roomCnt++;
		r.x = x;
		r.y = y;
		r.w = w;
		r.h = h;
	}
 
	/// Returns true, when the given area collides with existing rooms.
	bool checkColl(in uint x, in uint y, in uint w, in uint h) const pure nothrow {
		foreach (ref r; this.rooms[0 .. this.roomCnt]) {
			if (r.x + r.w + 1 >= x && r.x <= x + w + 1 &&
			    r.y + r.h + 1 >= y && r.y <= y + h + 1) {
				return true;
			}
		}
		return false;
	}
 
	/// Initializes and then builds the tiles from the room definitions.
	void buildTiles() pure nothrow {
		foreach (uint i; 0 .. this.tiles.length) {
			this.tiles[i].x = i % LEVEL_SIZE;
			this.tiles[i].y = i / LEVEL_SIZE;
			this.tiles[i].t = 0;
		}
		foreach (ref r; this.rooms[0 .. this.roomCnt]) {
			foreach (xi; r.x .. r.x + r.w + 1)
			foreach (yi; r.y .. r.y + r.h + 1) {
				this.tiles[yi * LEVEL_SIZE + xi].t = 1;
			}
		}
	}
 
	void dump() const @trusted {
		foreach (row; 0 .. LEVEL_SIZE) {
			immutable offset = LEVEL_SIZE * row;
			foreach (col; 0 .. LEVEL_SIZE) {
				write( this.tiles[offset + col].t );
			}
			writeln();
		}
	}
}
 
struct Random {
	uint current;
 
	uint next() nothrow {
		current += current;
		current ^= (current > int.max) ? 0x88888eee : 1;
		return current;
	}
}
 
__gshared Level[NUM_LEVS] levels;
 
void main(string[] args) @system {
	// Create a local random number generator
	immutable seed = (args.length > 1) ? args[1].to!uint() : 123;
	writefln( "The random seed is: %s", seed );
 
	// Create several levels for benchmarking purposes
	foreach (levelIdx, ref level; parallel( levels[] )) {
		auto rnd = Random( cast(uint) (seed * (levelIdx+1) * (levelIdx+1)) );
		foreach (i; 0 .. NUM_TRIES) {
			level.makeRoom(rnd);
			if (level.roomCnt == ROOMS) {
				break;
			}
		}
		level.buildTiles();
	}
 
	// Select the level with the most rooms for printing
	Level* levelToPrint = &levels[0];
	foreach (ref level; levels[1 .. $]) {
		if (level.roomCnt > levelToPrint.roomCnt) {
			levelToPrint = &level;
		}
	}
	levelToPrint.dump();
}
