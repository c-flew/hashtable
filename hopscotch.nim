import hashes, bitops

const
  H*: uint8 = sizeof(uint) * 8
  emptyHash: Hash = -1

type 
  hopscotch*[Key, Val] = tuple
    loadFactor: float32
    capacity: uint
    elements: uint

    keys: seq[Key]
    vals: seq[Val]

    bitmaps: seq[uint]
    hashes: seq[Hash]

    overflow: seq[(Key, Val)]

# forward declarations
proc setPos[Key, Val](t: var hopscotch[Key, Val], pos: uint, home: uint, key: Key, val: Val, hashInd: int)
proc removePos[Key, Val](t: var hopscotch[Key, Val], pos: uint, home: uint) {.inline.}
proc resize[Key, Val](t: var hopscotch[Key, Val], capacity: uint)
func p2(num: uint): uint {.inline.}
func fastMod(a: uint, b: uint): uint {.inline.}
func isEmpty[Key, Val](t: hopscotch[Key, Val], idx: uint): bool {.inline.}

proc initHopscotch*[Key, Val](capacity: uint = 16, lf: float32 = 0.75): hopscotch[Key, Val] =
  var capacity = p2 capacity
  var hashes = newSeq[Hash](capacity)
  for idx, elem in hashes:
    hashes[idx] = -1
  return (loadFactor: lf,
  capacity: capacity,
  elements: 0'u,
  keys: newSeq[Key](capacity),
  vals: newSeq[Key](capacity),
  bitmaps: newSeq[uint](capacity),
  hashes: hashes,
  overflow: @[])

proc put*[Key, Val](t: var hopscotch[Key, Val], key: Key, val: Val)  =
  if float32(t.capacity) * t.loadFactor < float32(t.elements):
    t.resize(t.capacity * 2)

  let hashInd = hash key
  let ind = fastMod(uint hashInd, t.capacity)

  if t.isEmpty(ind) or t.keys[ind] == key:
    t.setPos(ind, ind, key, val, hashInd)
  else:
    var posEmpty = ind
    while true:
      #echo ind, " ", posEmpty
      
      #maybe i should use overflow list instead of resize
      if posEmpty >= t.capacity:
        for idx, elem in t.overflow:
          if key == elem[0]:
            t.overflow[idx] = (key, val)
            return
        t.overflow.add((key, val))
        return 
      if t.isEmpty(posEmpty): break
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
      if t.isEmpty(uint check) or int(posEmpty) - check >= distLeft:
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
  t.hashes[pos] = hashInd
  echo "inserted ", key, " at ind ", pos, " with home ", home, " and cap ", t.capacity, " and hash ", fastMod(uint hashInd, t.capacity)

func find[Key, Val](t: hopscotch[Key, Val], key: Key): (Val, int, int) =
  let ind = fastMod(uint hash key, t.capacity)
  debugEcho "find ind ", ind
  # im pretty sure i dont have to worry about random init unlike in cpp
  debugEcho(ind, " ", t.capacity)
  if t.keys[ind] == key and not t.isEmpty(ind):
    return (t.vals[ind], int ind, int ind)
  else:
    var bits = t.bitmaps[ind]
    # dont recheck home bucked
    bits.clearBit(0)
    while bits != 0:
      # apparently firstSetBit is 1-indexed
      let pos: uint = uint firstSetBit(bits) - 1
      debugEcho pos
      if t.keys[ind + pos] == key and not t.isEmpty(ind + pos):
        return (t.vals[ind + pos], int ind + pos, int ind)
      bits.clearBit(pos)
 
  for idx, elem in t.overflow:
    if key == elem[0]:
      return (elem[1], idx, -1)

  # there has to be a better way to do this
  var ded: Val
  return (ded, -1, -1)


func get*[Key, Val](t: hopscotch[Key, Val], key: Key): (Val, bool) =
  let (val, ind, home) = t.find(key)
  return (val, ind != -1)

proc remove*[Key, Val](t: var hopscotch[Key, Val], key: Key) =
  let (val, ind, home) = t.find(key)
  echo "ind is ", ind
  if ind != -1:
    if home != -1:
      t.removePos(uint ind, uint home)
    else:
      t.overflow.delete(ind)

proc removePos[Key, Val](t: var hopscotch[Key, Val], pos: uint, home: uint) {.inline.} =
  echo "removing pos ", pos
  dec t.elements
  t.bitmaps[home].clearBit(pos - home)
  t.hashes[pos] = emptyHash


proc resize[Key, Val](t: var hopscotch[Key, Val], capacity: uint) =
  #let capacity = t.capacity * 2
  echo "capacity ", capacity
  var tmp = initHopscotch[Key, Val](capacity, t.loadFactor)

  for idx, h in t.hashes:
    if h != -1:
      tmp.put(t.keys[idx], t.vals[idx])
  
  tmp.overflow = t.overflow

  t = tmp

proc clear*[Key, Val](t: var hopscotch[Key, Val]) =
  for idx, h in t.hashes:
    if h != -1:
      t.removePos(idx, t.hashes[idx])

iterator pairs*[Key, Val](t: hopscotch[Key, Val]): (Key, Val) =
  for idx, h in t.hashes:
    if h != -1:
      yield (t.keys[idx], t.vals[idx])

proc debug*[Key, Val](t: hopscotch[Key, Val]) =
  debugEcho("in debug")
  for idx, h in t.hashes:
    debugEcho(idx, " ", t.keys[idx], " ", t.vals[idx], " ", h == -1)

func isEmpty[Key, Val](t: hopscotch[Key, Val], idx: uint): bool {.inline.} =
  t.hashes[idx] == emptyHash

func p2(num: uint): uint {.inline.} =
  uint rotateLeftBits(1'u, sizeof(uint) * 8 - countLeadingZeroBits(num - 1))

func fastMod(a: uint, b: uint): uint {.inline.} =
  a and (b - 1)

func elem*[Key, Val](t: hopscotch[Key, Val]): int =
  int(t.elements) + t.overflow.len
