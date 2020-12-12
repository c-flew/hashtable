import hopscotch, hashes

let ulim = 10000

var table: hopscotch[int, int] = initHopscotch[int, int](10, 0.75)
for i in 0..ulim:
  table.put(i, i*2)

for i in 0..ulim:
  #echo i
  let (val, found) = table.get(i)
  if not found or val != i * 2:
    echo "heh", i
    #echo i, " not found"

#let (val, found) = table.get(2207)
#echo "finchat ",found

#echo hash(2207) and (32768 - 1)

for i in 0..ulim:
  table.remove(i)
debug table
echo table.elements
echo table.capacity
