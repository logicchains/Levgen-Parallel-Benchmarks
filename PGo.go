package main

import (
	"flag"
	"fmt"
	"runtime"
	"time"
)

const (
	TileDim    = 50
	WidMin     = 2
	RestWidMax = 8
	NumLevs    = 800
	NumTries   = 50000
)

type Tile uint8

type Room struct {
	X, Y, W, H, N uint32
}


type Lev struct {
	ts []Tile
	rs []*Room
}

var seed uint32

func Rand(seed *uint32) (s uint32) {
	s = *seed
	s <<= 1
	sext := uint32(int32(s)>>31) & 0x88888eef
	s ^= sext ^ 1
	*seed = s
	return
}

func CheckColl(x, y, w, h uint32, rs []*Room) bool {
	for _, r := range rs {
		if (r.X+r.W+1) < x || r.X > (x+w+1) {
			continue
		}
		if (r.Y+r.H+1) < y || r.Y > (y+h+1) {
			continue
		}
		return true
	}
	return false
}

func MakeRoom(count uint32, seed *uint32) []*Room {
	rs := make([]*Room, 0, 100)
	for i := uint32(0); i < count; i++ {
		x := Rand(seed) % TileDim
		y := Rand(seed) % TileDim
		w := Rand(seed)%RestWidMax + WidMin
		h := Rand(seed)%RestWidMax + WidMin
		if x+w >= TileDim || y+h >= TileDim || x*y == 0 {
			continue
		}
		iscrash := CheckColl(x, y, w, h, rs)
		if !iscrash {
			rs = append(rs, &Room{x, y, w, h, uint32(len(rs))})
		}
		if len(rs) == 99 {
			break
		}
	}
	return rs
}

func Room2Tiles(r *Room, ts []Tile) {
	x := r.X
	y := r.Y
	w := r.W
	h := r.H
	for xi := x; xi <= x+w; xi++ {
		for yi := y; yi <= y+h; yi++ {
			num := yi*TileDim + xi
			ts[num] = 1
		}
	}
}

func PrintLev(l *Lev) {
	for i, t := range l.ts {
		fmt.Printf("%v", t)
		if i%(TileDim) == 49 && i != 0 {
			fmt.Print("\n")
		}
	}
}

func godo(levchan chan<- *Lev, seeds <-chan uint32) {
	for seed := range seeds {
		rs := MakeRoom(NumTries, &seed)
		ts := make([]Tile, 2500)
		for _, r := range rs {
			Room2Tiles(r, ts)
		}
		levchan <- &Lev{ts, rs}
	}
}

func main() {
	start := time.Now()
	nc := runtime.NumCPU()
	runtime.GOMAXPROCS(nc)
	vflag := flag.Int("v", 18, "Random Seed")
	flag.Parse()
	var v int = *vflag
	fmt.Printf("Random seed: %v\n", v)
	seed = ^uint32(v)
	levchan := make(chan *Lev, NumLevs)
	seeds := make(chan uint32, NumLevs)
	for i := 0; i < nc; i++ {
		go godo(levchan, seeds)
	}
	for i := uint32(0); i < NumLevs; i++ {
		seeds <- seed * (i + 1) * (i + 1)
	}
	var templ Lev
	for i := 0; i < NumLevs; i++ {
		x := <-levchan
		if len(x.rs) > len(templ.rs) {
			templ = *x
		}
	}
	PrintLev(&templ)
	fmt.Printf("Time in ms: %d\n", (time.Since(start) / 1000000))
}
