# Compile with nimrod c -d:release PN.nim

import os, strutils, unsigned

const
  TileDim = 50
  Miw = 2
  MaxWid = 8

  NumLevs = 800
  NumThreads = 4

type
  TTile = object
    x, y, t: int32
  TRoom = object
    x, y, w, h, n: int32
  TLev = object
    ts: array[2500, TTile]
    rs: array[100, TRoom]
    lenRs: int32

proc genRand(gen: ptr uint32): int32 {.raises: [], noSideEffect.} =
  var g = gen[]
  g += g
  g = g xor 1
  var tgen = cast[int32](g)
  if tgen < 0:
    g = g xor 0x88888eef
  gen[] = g
  return cast[int32](g)

proc checkColl(x, y, w, h: int32, rs: array[100, TRoom], lenRs: int32): int32 =
  result = 0
  for i in 0 .. <lenRs:
    let
      rx = rs[i].x
      ry = rs[i].y
      rw = rs[i].w
      rh = rs[i].h
    var roomOkay = ord((rx + rw + 1) < x) or ord(rx > (x + w + 1)) or
          ord((ry + rh + 1) < y) or ord(ry > (y + h + 1))
    if roomOkay == 0: return 1

proc makeRoom(rs: var array[100, TRoom], lenRs: ptr int32, gen: ptr uint32) =
  var newLenRs = lenRs[]
  for ii in 0 .. <50000:
    let
      x = genRand(gen) mod TileDim
      y = genRand(gen) mod TileDim
      w = genRand(gen) mod MaxWid+Miw
      h = genRand(gen) mod MaxWid+Miw

    if x + w >= TileDim or y + h >= TileDim or x == 0 or y == 0: continue
    let noCrash = checkColl(x, y, w, h, rs, newLenRs)
    if noCrash == 0:
      var r = TRoom(x: x, y: y, w: w, h: h, n: newLenRs)
      rs[newLenRs] = r
      newLenRs = newLenRs + 1

    if newLenRs == 99: break
  lenRs[] = newLenRs

proc room2Tiles(r: ptr TRoom, ts: var array[2500, TTile]) =
  let
    x = r.x
    y = r.y
    w = r.w
    h = r.h
  
  for xi in x .. x + w:
    for yi in y .. y + h:
      var num = yi * TileDim + xi
      ts[num].t = 1

proc printLev(lvl: ptr TLev) =
  for i in 0 .. <2500:
    stdout.write(lvl.ts[i].t)
    if i mod TileDim == 49 and i != 0: stdout.write("\n")

var
  ls: array[NumLevs, TLev]
  gens: array[NumThreads, array[8, uint32]]

proc makeLevs(threadNum: int32) =
  var
    loopStart = threadNum * (NumLevs div NumThreads)
    pGen = addr(gens[threadNum][0])
  for i in loopStart .. <(loopStart + (NumLevs div NumThreads)):
    var
      rs {.noinit.}: array[100, TRoom]
      lenRs = 0'i32
      pLenRs = addr(lenRs)
    makeRoom(rs, pLenRs, pGen)
    
    var ts {.noinit.}: array[2500, TTile]
    for ii in 0 .. <2500:
      let imod = ii mod TileDim
      let idiv = ii.int32 div TileDim
      ts[ii].x = imod
      ts[ii].y = idiv
      ts[ii].t = 0
    for ii in 0 .. <lenRs:
      room2Tiles(addr(rs[ii]), ts)
    var lvl: TLev
    lvl.rs = rs
    lvl.ts = ts
    lvl.lenRs = lenRs
    ls[i] = lvl

when isMainModule:
  let v = paramStr(1).parseInt()
  echo("The random seed is: ", v)
  # TODO: Seed random? srand(v)
  
  var gen = v
  for i in 0 .. <NumThreads:
    gens[i][0] = uint32(gen * (i+1) * (i+1))
    echo "The seed of thread $1 is: $2" % [$(i+1), $gens[i][0]]
  
  for i in 0 || <NumThreads:
    makeLevs(i.int32)
  
  var templ: TLev
  templ.lenRs = 0
  for i in 0 .. <100:
    if ls[i].lenRs > templ.lenRs: templ = ls[i]
  printLev(addr(templ))
