use std::{os, int, uint,u32, vec,comm};

static TileDim: u32 = 50;
static MinWid: u32  = 2;
static MaxWid: u32  = 8;

static NumLevs: uint= 800; 
static NumCores: uint = 4;
static NumTries: uint = 50000;

fn main() {
    let args = os::args();
    let str = (args[1]);
    let v = int::from_str(str).get_or_default(18);
    println(fmt!("The random seed is: %?",v));

    let prng: u32 = v.to_u32();
    let (port, chan) = stream();
    let chan = comm::SharedChan::new(chan);
    for uint::range(0,NumCores)|val| {
        let child_chan = chan.clone();
        do spawn {
            let thisnum = val.to_u32()+1;
            let mut newprng = prng.clone()*thisnum*thisnum;
            child_chan.send(MakeLevs(NumLevs/NumCores,&mut newprng));
        }
    }
    let mut ls: ~[Lev] = ~[];
    let mut ii :uint = 0;
    while ii < NumCores{
        ls = vec::append(ls,port.recv() );
        ii+=1;
    }
    let biggest_lev = find_most_rooms(ls);
    print_lev(biggest_lev);
}

fn MakeLevs(n: uint, gen:&mut u32) -> ~[Lev] {
    let ls: ~[Lev] = do vec::from_fn(n) |_| {
        let rs = rooms(99, gen);
        let mut ts: ~[Tile] = do vec::from_fn( (TileDim * TileDim).to_uint() ) |ii| {
            Tile {
                x: ii.to_u32() % TileDim,
                y: ii.to_u32() / TileDim,
                t: false
            }
        };

        for rs.iter().advance |r| {
            room_to_tiles(r, &mut ts);
        }
        Lev { tiles: ts, rooms: rs }
    }; 
    ls   
}

struct Tile {
    x: u32,
    y: u32,
    t: bool
}

struct Room {
    x: u32,
    y: u32,
    w: u32,
    h: u32,
    n: u32
}

struct Lev {
    tiles: ~[Tile],
    rooms: ~[Room],
}

fn find_most_rooms<'a>(ls: &'a [Lev]) -> &'a Lev {
    do ls.iter().max_by |lev| {
        lev.rooms.len()
    }.expect("oops, no levels")
}

fn rooms(n: uint,gen:&mut u32) -> ~[Room] {
    let mut rooms = vec::with_capacity(n);
    for NumTries.times {
	let x = GenRand(gen) % TileDim;
	let y = GenRand(gen) % TileDim;
	let w = GenRand(gen) % MaxWid+MinWid;
	let h = GenRand(gen) % MaxWid+MinWid;
        if x + w < TileDim &&
           y + h < TileDim &&
           x != 0 &&
           y != 0 &&
           not_crash(x, y, w, h, rooms) {
            let r = Room { x: x, y: y, w: w, h: h, n: rooms.len().to_u32() };
            rooms.push(r);
            if rooms.len() == n { break }
        }
    }
    rooms
}

fn not_crash(new_x: u32, new_y: u32, new_w: u32, new_h: u32, rs: &[Room]) -> bool {
    do rs.iter().all |r| {
        let Room { x, y, w, h, _ } = *r;

        ((x + w + 1) < new_x ||
         x > (new_x + new_w + 1) ||
         (y + h + 1) < new_y ||
         y > (new_y + new_h + 1))
    }
}

fn room_to_tiles(r: &Room, ts: &mut ~[Tile]) {
    let Room { x, y, w, h, _ } = *r;

    for u32::range(y, y + h + 1) |yi| {
        for u32::range(x, x + w + 1) |xi| {
            let num = yi * TileDim + xi;
            ts[num].t = true;
        }
    }
}

fn print_lev(l: &Lev) {
    for l.tiles.iter().enumerate().advance |(i, tile)| {
        print(if tile.t {"1"} else {"0"});
        if (i).to_u32() % TileDim == 49 {
            print("\n");
        }
    }
}

fn GenRand(gen:&mut u32) ->u32 { 
	*gen += *gen;
        *gen ^= 1;
	if  (*gen).to_i32() < 0 {
              *gen ^= 0x88888eef;
         }
	return *gen
}
