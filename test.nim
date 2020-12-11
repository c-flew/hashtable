import hopscotch

var table: hopscotch[int, int] = initHopscotch[int, int](10, 0.75)
table.put(1, 2)
echo table.get(1)
debug(table)
table.resize()
debug(table)
echo "\n\n\n"
discard table.remove(1)
debug(table)
table.resize()
debug(table)
