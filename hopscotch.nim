import hashes, bitops

const
  # As H is equivalent to default int/uint size, 
  # there are no bits leftover to use for meta data like checking for empty/overflow
  H*: uint8 = sizeof(uint) * 8

  # hash to indicate a bucket is empty
  emptyHash: Hash = -1
  
  defaultSize: uint = 16

type 
  hopscotch*[Key, Val] = tuple
    # (high, low)
    loadFactor: (float32, float32)
    capacity: uint
    elements: uint

    keys: seq[Key]
    vals: seq[Val]

    bitmaps: seq[uint]
    hashes: seq[Hash]

    overflow: seq[(Key, Val)]

# forward declarations
proc setPos[Key, Val](t: var hopscotch[Key, Val], pos: uint, home: uint, key: Key, val: Val, hashInd: int) {.inline.}
proc removePos[Key, Val](t: var hopscotch[Key, Val], pos: uint, home: uint) {.inline.}
proc resize[Key, Val](t: var hopscotch[Key, Val], capacity: uint)
func p2(num: uint): uint {.inline.}
func fastMod(a: uint, b: uint): uint {.inline.}
func isEmpty[Key, Val](t: hopscotch[Key, Val], idx: uint): bool {.inline.}
func lsb(mask: uint): int {.inline.}

proc initHopscotch*[Key, Val](capacity: uint = 16, lfHigh: float32 = 0.75, lfLow: float32 = 0.2): hopscotch[Key, Val] =
  # ensure capacity is power of 2 such that fastMod works
  var capacity = p2 capacity

  # there might be a better way to init the hashes seq
  # but not performance wise afaik
  var hashes = newSeq[Hash](capacity)
  for idx, elem in hashes:
    hashes[idx] = emptyHash

  return (loadFactor: (lfHigh, lfLow),
  capacity: capacity,
  elements: 0'u,
  keys: newSeq[Key](capacity),
  vals: newSeq[Key](capacity),
  bitmaps: newSeq[uint](capacity),
  hashes: hashes,
  overflow: @[])

proc put*[Key, Val](t: var hopscotch[Key, Val], key: Key, val: Val)  =
  if float32(t.capacity) * t.loadFactor[0] < float32(t.elements):
    t.resize(t.capacity * 2)

  let hashInd = hash key
  let ind = fastMod(uint hashInd, t.capacity)

  if t.isEmpty(ind) or t.keys[ind] == key:
    t.setPos(ind, ind, key, val, hashInd)
  else:
    var posEmpty = ind
    while true:

      # checks if posEmpty is outside bucket list
      # this commonly happens when a key hashes near the end of the list
      # unfortunately this usually leads to keys 
      # getting put in the overflow list due to the nature of hopscotch
      if posEmpty >= t.capacity:
        for idx, elem in t.overflow:
          if key == elem[0]:
            t.overflow[idx] = (key, val)
            return
        t.overflow.add((key, val))
        return 

      if t.isEmpty(posEmpty): break
      inc posEmpty
    
    # i didnt know that nim couldnt perform operations on two different number types
    # until it was too late
    # TODO: rethink number type choices
    var check = int(posEmpty) - int(H - 1)
    while int(posEmpty) - int(ind) >= int(H):
      let home = fastMod(uint t.hashes[check], t.capacity)
      let distLeft = (int(H) - 1) - (check - int home)
      if t.isEmpty(uint check) or int(posEmpty) - check >= distLeft:
        inc check
        continue
      
      # move check to empty position
      t.setPos(posEmpty, home, t.keys[check], t.vals[check], t.hashes[check])
      t.removePos(uint check, home)

      # update pos empty and check
      posEmpty = uint check
      check -= (int(H) - int 1)
    t.setPos(posEmpty, ind, key, val, hashInd)

proc `[]=`*[Key, Val](t: var hopscotch[Key, Val], key: Key, val: sink Val) {.inline.} =
  t.put(key, val)

proc setPos[Key, Val](t: var hopscotch[Key, Val], pos: uint, home: uint, key: Key, val: Val, hashInd: int) {.inline.}  =
  t.keys[pos] = key
  t.vals[pos] = val
  t.bitmaps[home].setBit(uint8(pos - home))
  inc t.elements
  t.hashes[pos] = hashInd

func find[Key, Val](t: hopscotch[Key, Val], key: Key): (Val, int, int) =
  let ind = fastMod(uint hash key, t.capacity)
  if t.keys[ind] == key and not t.isEmpty(ind):
    return (t.vals[ind], int ind, int ind)
  else:

    # the following is my change to the linear probing used in hopscotch
    # this takes the bitmask of the home bucket 
    # and loops through all the set bits
    # by counting the leading zeroes and then clearing that bit
    # this might improve performance on x64 cpus due to the bsr instruction
    # but I am not sure about performance on arm due to a lack of an equivalent instruction
    # also this approach might get beat by compiler optimizations
    # and thus this is likely a slower approach
    # TODO: benchmark this vs linear probing

    var bits = t.bitmaps[ind]
    # dont recheck home bucked
    bits.clearBit(0)
    while bits != 0:
      let pos: uint = uint lsb bits
      if t.keys[ind + pos] == key and not t.isEmpty(ind + pos):
        return (t.vals[ind + pos], int ind + pos, int ind)
      bits.clearBit(pos)
 
  for idx, elem in t.overflow:
    if key == elem[0]:
      return (elem[1], idx, -1)

  # there has to be a better way to do this
  # (init default of given type)
  var ded: Val
  return (ded, -1, -1)


func get*[Key, Val](t: hopscotch[Key, Val], key: Key): (Val, bool) =
  let (val, ind, home) = t.find(key)

  # (val, found)
  return (val, ind != -1)

proc remove*[Key, Val](t: var hopscotch[Key, Val], key: Key) =
  let (val, ind, home) = t.find(key)
  if ind != -1:
    if home != -1:
      t.removePos(uint ind, uint home)
    else:
      t.overflow.delete(ind)

  if t.capacity > defaultSize and float32(t.elements) < float32(t.capacity) * t.loadFactor[1]:
    t.resize(uint rotateRightBits(t.capacity, 1))

proc removePos[Key, Val](t: var hopscotch[Key, Val], pos: uint, home: uint) {.inline.} =
  # key and val dont need to be cleared
  dec t.elements
  t.bitmaps[home].clearBit(pos - home)
  t.hashes[pos] = emptyHash


proc resize[Key, Val](t: var hopscotch[Key, Val], capacity: uint) =
  # changing of capacity is done on method call
  # i.e.
  # t.resize(t.capacity * 2)
  # since this method isnt exposed to the user it shouldnt matter
  # and it makes it a tad more convenient for me
  var tmp = initHopscotch[Key, Val](capacity, t.loadFactor[0], t.loadFactor[1])

  for idx, h in t.hashes:
    if h != emptyHash:
      tmp.put(t.keys[idx], t.vals[idx])
  
  tmp.overflow = t.overflow
  t = tmp

proc clear*[Key, Val](t: var hopscotch[Key, Val]) =
  for idx, h in t.hashes:
    if h != emptyHash:
      t.removePos(idx, t.hashes[idx])

iterator pairs*[Key, Val](t: hopscotch[Key, Val]): (Key, Val) =
  for idx, h in t.hashes:
    if h != emptyHash:
      yield (t.keys[idx], t.vals[idx])

proc toHopscotch*[Key, Val](pairs: openArray[(Key, Val)]): hopscotch[Key, Val] =
  result = initHopscotch[Key, Val]()

  for (k, v) in pairs:
    result.put(k, v)


proc debug*[Key, Val](t: hopscotch[Key, Val]) =
  debugEcho("in debug")
  for idx, h in t.hashes:
    debugEcho(idx, " ", t.keys[idx], " ", t.vals[idx], " ", h == emptyHash)

func isEmpty[Key, Val](t: hopscotch[Key, Val], idx: uint): bool {.inline.} =
  # Using unhashed hashes replaces the need for seq to check empty buckets
  t.hashes[idx] == emptyHash

# this doesnt work if mask = 0, but that is already checked in find
func lsb(mask: uint): int =
  63 - countLeadingZeroBits(mask)

# see:
# https://jameshfisher.com/2018/03/30/round-up-power-2/ 
func p2(num: uint): uint {.inline.} =
  uint rotateLeftBits(1'u, sizeof(uint) * 8 - countLeadingZeroBits(num - 1))

# see the "Performance issues" section of the following
# https://en.wikipedia.org/wiki/Modulo_operation#Variants_of_the_definition
# basically this works as regular mod as long as b is power of 2
func fastMod(a: uint, b: uint): uint {.inline.} =
  a and (b - 1)

func elem*[Key, Val](t: hopscotch[Key, Val]): int {.inline.} =
  int(t.elements) + t.overflow.len
