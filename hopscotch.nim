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

    overflow: seq[(Key, Val)]

# forward declarations
proc setPos[Key, Val](t: var hopscotch[Key, Val], pos: uint, home: uint, key: Key, val: Val, hashInd: int)
proc removePos[Key, Val](t: var hopscotch[Key, Val], pos: uint, home: uint) {.inline.}
proc resize[Key, Val](t: var hopscotch[Key, Val], capacity: uint)
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
  empty: empty,
  overflow: @[])

proc put*[Key, Val](t: var hopscotch[Key, Val], key: Key, val: Val)  =
  let hashInd = hash key
  let ind = fastMod(uint hashInd, t.capacity)
  if float32(t.capacity) * t.loadFactor < float32(t.elements):
    echo "resize 1"
    t.resize(t.capacity * 2)

  if t.empty[ind]:
    t.setPos(ind, ind, key, val, hashInd)
  else:
    var posEmpty = ind
    while true:
      #echo ind, " ", posEmpty
      
      #maybe i should use overflow list instead of resize
      if posEmpty >= t.capacity: 
        echo "resize 2"
        t.resize(t.capacity * 2)
        t.put(key, val)
        return
      if t.empty[posEmpty]: break
      inc posEmpty
    
    var check = int(posEmpty) - int(H - 1)
    #echo "check ", check
    echo "cond ", int(posEmpty) - int(ind) > int(H)
    while int(posEmpty) - int(ind) > int(H):
      let home = fastMod(uint t.hashes[check], t.capacity)
      let distLeft = (int(H) - 1) - (check - int home)
      echo "distleft ", distLeft
      echo "dist to tot ", posEmpty - home
      echo "dis to move ", int(posEmpty) - check
      echo "testing ", distLeft >= int(posEmpty) - check
      if t.empty[check] or int(posEmpty) - check >= distLeft:
        inc check
        continue
      
      # move check to empty position
      t.setPos(posEmpty, home, t.keys[check], t.vals[check], t.hashes[check])
      t.removePos(uint check, home)

      # update pos empty and check
      posEmpty = uint check
      check -= (int(H) - int 1)
    echo "pos empty ", posEmpty
    t.setPos(posEmpty, ind, key, val, hashInd)

proc `[]=`*[Key, Val](t: hopscotch[Key, Val], key: Key, val: sink Val) =
  t.put(key, val)

proc setPos[Key, Val](t: var hopscotch[Key, Val], pos: uint, home: uint, key: Key, val: Val, hashInd: int)  =
  t.keys[pos] = key
  t.vals[pos] = val
  echo "did we make it here?"
  t.bitmaps[home].setBit(uint8(pos - home))
  inc t.elements
  t.empty[pos] = false
  t.hashes[pos] = hashInd
  echo "inserted ", key, " at ind ", pos, " with home ", home, " and cap ", t.capacity

func find[Key, Val](t: hopscotch[Key, Val], key: Key): (Val, int, int) =
  let ind = fastMod(uint hash key, t.capacity)

  # im pretty sure i dont have to worry about random init unlike in cpp
  debugEcho(ind, " ", t.capacity)
  if t.keys[ind] == key:
    return (t.vals[ind], int ind, int ind)
  else:
    var bits = t.bitmaps[ind]
    # dont recheck home bucked
    bits.clearBit(0)
    while bits != 0:
      # apparently firstSetBit is 1-indexed
      let pos: uint = uint firstSetBit(bits) - 1
      debugEcho pos
      if t.keys[ind + pos] == key:
        return (t.vals[ind + pos], int ind + pos, int ind)
      bits.clearBit(pos)
 
  # there has to be a better way to do this
  var ded: Val
  return (ded, -1, -1)


func get*[Key, Val](t: hopscotch[Key, Val], key: Key): (Val, bool) =
  let (val, ind, home) = t.find(key)
  return (val, ind != -1)

proc remove*[Key, Val](t: var hopscotch[Key, Val], key: Key) =
  let (val, ind, home) = t.find(key)
  if ind != -1:
    t.removePos(uint ind, uint home)
  else:
    echo "burh ",key

proc removePos[Key, Val](t: var hopscotch[Key, Val], pos: uint, home: uint) {.inline.} =
  t.empty[pos] = true
  dec t.elements
  t.bitmaps[home].clearBit(pos - home)


proc resize[Key, Val](t: var hopscotch[Key, Val], capacity: uint) =
  #let capacity = t.capacity * 2
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
