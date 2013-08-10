// Compile with:
// ldmd2 -noruntime -release -inline -O -noboundscheck bench2.d

import core.stdc.stdio, core.stdc.stdlib, std.concurrency;;

enum int TileDim = 50;
enum int Miw = 2;
enum int MaxWid = 8;

enum int NumThreads=4;
enum int NumLevs=800;
enum int NumTries=50000;

struct Tile {
    int X = void;
    int Y = void;
    int T = void;
}

struct Room {
    int X = void;
    int Y = void;
    int W = void;
    int H = void;
    int N = void;
}

struct Lev {
    Tile[2500] ts = void;
    Room[100] rs = void;
    int lenrs = void;
}

int GenRand(uint* gen) pure nothrow {
    *gen += *gen;
    *gen ^= 1;
    int tgen = *gen;
    if (tgen < 0) {
        *gen ^= 0x88888eef;
    }
    int a = *gen;
    return a;
}

int CheckColl(in int x, in int y, in int w, in int h,
              shared in ref Room[100] rs, in int lenrs) pure nothrow {
    for (int i = 0; i < lenrs; i++) {
        int rx = rs[i].X;
        int ry = rs[i].Y;
        int rw = rs[i].W;
        int rh = rs[i].H;
        int RoomOkay = void;
        if ((rx + rw + 1) < x || rx > (x + w + 1)) {
            RoomOkay = 1;
        } else if ((ry + rh + 1) < y || ry > (y + h + 1)) {
            RoomOkay = 1;
        } else {
            RoomOkay = 0;
        }
        if (RoomOkay == 0)
            return 1;
    }
    return 0;
}

void MakeRoom(shared ref Room rs[100], int* lenrs, uint* gen) pure nothrow {
    immutable int x = GenRand(gen) % TileDim;
    immutable int y = GenRand(gen) % TileDim;
    immutable int w = GenRand(gen) % MaxWid+Miw;
    immutable int h = GenRand(gen) % MaxWid+Miw;
    
    if (x + w >= TileDim || y + h >= TileDim || x == 0 || y == 0)
        return;
    immutable int nocrash = CheckColl(x, y, w, h, rs, *lenrs);
    if (nocrash == 0) {
        Room r = void;
        r.X = x;
        r.Y = y;
        r.W = w;
        r.H = h;
        r.N = *lenrs;
        rs[*lenrs] = r;
        *lenrs = *lenrs + 1;
    }
}

void Room2Tiles(shared in Room* r, shared ref Tile ts[2500]) pure nothrow {
    immutable x = r.X;
    immutable y = r.Y;
    immutable w = r.W;
    immutable h = r.H;
    for (int xi = x; xi <= x + w; xi++) {
        for (int yi = y; yi <= y + h; yi++) {
            int num = yi * TileDim + xi;
            ts[num].T = 1;
        }
    }
}

void PrintLev(shared in Lev* l) nothrow {
    for (int i = 0; i < 2500; i++) {
        printf("%d", l.ts[i].T);
        if (i % (TileDim) == 49 && i != 0)
            printf("\n");
    }
}

shared Lev[NumLevs] ls = void;

void MakeLevs(const uint strNum,const uint Pgen,shared Lev[NumLevs] *ls) {
    uint genHere = Pgen; 
    int startPoint = strNum*(NumLevs/NumThreads);
    for (int i = startPoint; i < startPoint+NumLevs/NumThreads; i++) { 
        shared Room rs[100] = void;
        int lenrs = 0;
        int *Plenrs = &lenrs;
        int ii = void;
        for (ii = 0; ii < NumTries; ii++) {
            MakeRoom(rs, Plenrs, &genHere);
            if (lenrs == 99) {
                break;
            }
        }
        shared Tile[2500] ts = void;
        for (ii = 0; ii < 2500; ii++) {
            ts[ii].X = ii % TileDim;
            ts[ii].Y = ii / TileDim;
            ts[ii].T = 0;
        }
        for (ii = 0; ii < lenrs; ii++) {
            Room2Tiles(&(rs[ii]), ts);
        }
        shared Lev l = void;
        l.rs = rs;
        l.ts = ts;
        l.lenrs = lenrs;
	      (*ls)[i]=l;
    }
    auto ownerID = ownerTid();
    send(ownerID,true);
}

void main(string[] args)   {
    int v = atoi(args[1].ptr);
    printf("The random seed is: %d \n", v);
    srand(v);
    uint gen = v;
    uint *Pgen = &gen;
    Tid threads[NumThreads];
    for (int i=0;i<NumThreads;i++){
	    const uint thisGen = *Pgen*(i+1)*(i+1);
	    const uint ii = i;
      auto tid = spawn(&MakeLevs, ii,thisGen,&ls);
	    threads[i]=tid;
    }    
    for (int i=0;i<NumThreads;i++){
	    auto done = receiveOnly!(bool)();
	    while (done==false){};
    }
    shared Lev templ = void;
    templ.lenrs = 0;
    for (int i = 0; i < NumLevs; i++) {
	    if (ls[i].lenrs > templ.lenrs)
            templ = ls[i];
    }
 
    PrintLev(&templ);
}
