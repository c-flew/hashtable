import hashes, bitops

const H*: uint8 = sizeof(uint) * 8

type 
  hopscotch*[Key, Val] = tuple
    loadFactor: float32
    capacity: uint
    elements: uint

    keys: seq[Key]
    vals: seq[Val]

    bitmaps: seq[uint]
    hashes: seq[Hash]
    empty: seq[bool]

# forward declarations
proc setPos[Key, Val](t: var hopscotch[Key, Val], pos: uint, home: uint, key: Key, val: Val, hashInd: int) 
proc removePos[Key, Val](t: var hopscotch[Key, Val], pos: uint, home: uint) {.inline.}
proc resize*[Key, Val](t: var hopscotch[Key, Val])
func p2(num: uint): uint {.inline.}
func fastMod(a: uint, b: uint): uint {.inline.}

proc initHopscotch*[Key, Val](capacity: uint = 16, lf: float32 = 0.75): hopscotch[Key, Val] =
  var capacity = p2 capacity
  var empty = newSeq[bool](capacity)
  for idx, emp in empty.pairs:
    empty[idx] = true
  return (loadFactor: lf,
  capacity: capacity,
  elements: 0'u,
  keys: newSeq[Key](capacity),
  vals: newSeq[Key](capacity),
  bitmaps: newSeq[uint](capacity),
  hashes: newSeq[Hash](capacity),
  empty: empty)

proc put*[Key, Val](t: var hopscotch[Key, Val], key: Key, val: Val)  =
  let hashInd = hash key
  let ind = fastMod(uint hashInd, t.capacity)
  if float32(t.capacity) * t.loadFactor < float32(t.elements):
    resize(t)

  if t.empty[ind]:
    t.setPos(ind, ind, key, val, hashInd)
  else:
    var posEmpty = 0'u
    while true:
      if t.empty[ind + posEmpty]: break
      inc posEmpty
    
    var check = posEmpty - (H - 1)
    while posEmpty - ind > H:
      let home = fastMod(uint t.hashes[check], t.capacity)
      let distLeft = (H - 1) - (check - home)
      if t.empty[check] and distLeft >= posEmpty - check:
        inc check
        continue
      
      # move check to empty position
      t.setPos(posEmpty, home, t.keys[check], t.vals[check], t.hashes[check])
      t.removePos(check, home)

      # update pos empty and check
      posEmpty = check
      check -= (H - 1)

    t.setPos(ind + posEmpty, ind, key, val, hashInd)

proc `[]=`*[Key, Val](t: hopscotch[Key, Val], key: Key, val: sink Val) =
  t.put(key, val)

proc setPos[Key, Val](t: var hopscotch[Key, Val], pos: uint, home: uint, key: Key, val: Val, hashInd: int)  =
  t.keys[pos] = key
  t.vals[pos] = val
  t.bitmaps[pos].setBit(uint8(pos - home))
  inc t.elements
  t.empty[pos] = false
  t.hashes[pos] = hashInd

func find[Key, Val](t: hopscotch[Key, Val], key: Key): (Val, int, int) =
  let ind = fastMod(uint hash key, t.capacity)

  # im pretty sure i dont have to worry about random init unlike in cpp
  debugEcho(ind)
  if t.keys[ind] == key:
    return (t.vals[ind], int ind, int ind)
  else:
    var bits = t.bitmaps[ind]
    
    # dont recheck home bucked
    bits.clearBit(0)
    while bits != 0:
      # apparently firstSetBit is 1-indexed
      let pos: uint = uint firstSetBit(bits) - 1
      if t.keys[ind + pos] == key:
        return (t.vals[ind + pos], int ind + pos, int ind)
      bits.clearBit(ind)
 
  # there has to be a better way to do this
  var ded: Val
  return (ded, -1, -1)


func get*[Key, Val](t: hopscotch[Key, Val], key: Key): (Val, bool) =
  let (val, ind, home) = t.find(key)
  return (val, ind != -1)

proc remove*[Key, Val](t: var hopscotch[Key, Val], key: Key): bool =
  let (val, ind, home) = t.find(key)
  if ind != -1:
    echo "burh"
    t.removePos(uint ind, uint home)
    return true

  return false

proc removePos[Key, Val](t: var hopscotch[Key, Val], pos: uint, home: uint) {.inline.} =
  t.empty[pos] = true
  dec t.elements
  t.bitmaps[home].clearBit(pos - home)


proc resize*[Key, Val](t: var hopscotch[Key, Val]) =
  let capacity = t.capacity * 2
  echo "capacity ", capacity
  var tmp = initHopscotch[Key, Val](capacity, t.loadFactor)

  for idx, emp in t.empty:
    if not emp:
      tmp.put(t.keys[idx], t.vals[idx])

  t = tmp

proc debug*[Key, Val](t: hopscotch[Key, Val]) =
  debugEcho("in debug")
  for idx, emp in t.empty:
    debugEcho(idx, " ", t.keys[idx], " ", t.vals[idx], " ", t.empty[idx])


func p2(num: uint): uint {.inline.}= 
  uint rotateLeftBits(1'u, sizeof(uint) * 8 - countLeadingZeroBits(num - 1))

func fastMod(a: uint, b: uint): uint {.inline.} =
  a and (b - 1)
