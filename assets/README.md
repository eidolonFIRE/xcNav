# Airports.json

Pull from here: https://github.com/mwgg/Airports/blob/master/airports.json

Find-replace with:

`\{\n\s+"name": ("[^"]+",)\s+"elevation": ([-\d]+),\s+"lat": ([-\d.]+,)\s+"lon": ([-\d\.]+,)\s+\}`
`[$1 $3 $4 $2]`
