package main

import (
  "flag"
	"fmt"
	"runtime"
	"time"
)

const (
	TileDim = 50
	MinWid  = 2
	MaxWid  = 8
	NumLevs = 800
	NumTries = 50000
)

type Tile struct {
	X uint32
	Y uint32
	T uint32
}

type Room struct {
	X uint32
	Y uint32
	W uint32
	H uint32
	N uint32
}

type Lev struct {
	ts *[]Tile
	rs []Room
}

var seed uint32

func Rand(seed *uint32) uint32 {
	*seed <<= 1
        sext := uint32(int32(*seed)>>31) & 0x88888eef
	*seed ^= sext ^ 1
	return *seed

}


func CheckColl(x, y, w, h uint32, rs []Room) bool {
	var r *Room
	for i := range rs {
		r = &rs[i]
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

func MakeRoom(count uint32, seed *uint32) *[]Room {
	rs := make([]Room, 100)
	counter := uint32(0)
	for i := uint32(0); i < count; i++ {
		x := Rand(seed) % TileDim
		y := Rand(seed) % TileDim
		if x*y == 0 {
			continue
		}
		w := Rand(seed)%MaxWid + MinWid
		h := Rand(seed)%MaxWid + MinWid
		if x+w >= TileDim || y+h >= TileDim {
			continue
		}
		iscrash := CheckColl(x, y, w, h, rs[0:counter])
		if iscrash == false {
			rs[counter] = Room{x, y, w, h, counter}
			counter++
		}
		if counter == 99 {
			break
		}
	}
	x := rs[0:counter]
	return &x
}

func Room2Tiles(r *Room, ts *[]Tile) {
	x := r.X
	y := r.Y
	w := r.W
	h := r.H
	for xi := x; xi <= x+w; xi++ {
		for yi := y; yi <= y+h; yi++ {
			num := yi*TileDim + xi
			(*ts)[num].T = 1
		}
	}
}

func PrintLev(l *Lev) {
	for i, t := range *l.ts {
		fmt.Printf("%v", t.T)
		if i%(TileDim) == 49 && i != 0 {
			fmt.Print("\n")
		}
	}
}

func godo(limchan chan bool, levchan chan *Lev, seed *uint32) {
	rs := MakeRoom(NumTries,seed)
	ts := make([]Tile, 2500)
	for ii := uint32(0); ii < 2500; ii++ {
		ts[ii] = Tile{X: ii % TileDim, Y: ii / TileDim, T: 0}
	}
	for _, r := range *rs {
		Room2Tiles(&r, &ts)
	}
	lev := &Lev{&ts, *rs}
	levchan <- lev
	limchan <- false
}

var vflag = flag.Int("v", 18, "Random Seed")

func main() {
	start := time.Now()
	nc := runtime.NumCPU()
	runtime.GOMAXPROCS(nc)
	limchan := make(chan bool, nc)
	levchan := make(chan *Lev, NumLevs)
	for i := 0; i < nc; i++ {
		limchan <- false
	}
	flag.Parse()
	var v int = *vflag
	fmt.Printf("Random seed: %v\n", v)
	seed = ^uint32(v)
	var i uint32
	for i = 0; i < NumLevs; i++ {
		<-limchan
		newseed := seed*(i+1)*(i+1)
		go godo(limchan, levchan,&newseed)
	}
	templ := Lev{}
	for i := 0; i < NumLevs; i++ {
		x := <-levchan
		if len((*x).rs) > len(templ.rs) {
			templ = *x
		}
	}
	PrintLev(&templ)
	end := time.Now()
	fmt.Printf("Time in ms: %d\n", (end.Sub(start) / 1000000))
}
