# Sourced from:
# https://openflights.org/data.html

import csv
import json

data_airports = []

# read data
with open("airports/airports.dat", "r", encoding="utf8") as infile:
    reader = csv.reader(infile)
    data_airports.extend(reader)



# 0) Airport ID	Unique OpenFlights identifier for this airport.
# 1) Name	Name of airport. May or may not contain the City name.
# 2) City	Main city served by airport. May be spelled differently from Name.
# 3) Country	Country or territory where airport is located. See Countries to cross-reference to ISO 3166-1 codes.
# 4) IATA	3-letter IATA code. Null if not assigned/unknown.
# 5) ICAO	4-letter ICAO code.
# 6) Null if not assigned.
# 7) Latitude	Decimal degrees, usually to six significant digits. Negative is South, positive is North.
# 8) Longitude	Decimal degrees, usually to six significant digits. Negative is West, positive is East.
# 9) Altitude	In feet.
# 10) Timezone	Hours offset from UTC. Fractional hours are expressed as decimals, eg. India is 5.5.
# 11) DST	Daylight savings time. One of E (Europe), A (US/Canada), S (South America), O (Australia), Z (New Zealand), N (None) or U (Unknown). See also: Help: Time
# 12) Tz database time zone	Timezone in "tz" (Olson) format, eg. "America/Los_Angeles".
# 13) Type	Type of the airport. Value "airport" for air terminals, "station" for train stations, "port" for ferry terminals and "unknown" if not known. In airports.csv, only type=airport is included.
# 14) Source	Source of this data. "OurAirports" for data sourced from OurAirports, "Legacy" for old data not matched to OurAirports (mostly DAFIF), "User" for unverified user contributions. In airports.csv, only source=OurAirports is included.



# 0         1              2             3             4       5          6            7            8   9   10          11                  12          13
# 2, "Madang Airport", "Madang", "Papua New Guinea", "MAG", "AYMD", -5.20707988739, 145.789001465, 20, 10, "U", "Pacific/Port_Moresby", "airport", "OurAirports"


outdata = {}

# Airports
for each in data_airports:
    key = each[4]
    if key not in ["\\N"]:
        if key not in outdata:
            outdata[key] = [each[1], float(each[6]), float(each[7]), float(each[8]) * 0.3048]
        else:
            print(f"/!\\ Code conflict. {key}")






data_dafif = []

# read data
with open("airports/airports-dafif.dat", "r", encoding="utf8") as infile:
    reader = csv.reader(infile)
    data_dafif.extend(reader)

# 0) Country code
# 1) Name
# 2) Code
# 3) ?
# 4) Long
# 5) Lat
# 5) Alt

#  0    1        2  3     4           5        6
# AE, Arzanah, OMAR, , 52.559944, 24.780528, 00015



# DAFIF
for each in data_dafif:
    key = each[2]
    if key not in ["\\N"]:
        if key not in outdata:
            outdata[key] = [each[1], float(each[5]), float(each[4]), float(each[6]) * 0.3048]
        else:
            print(f"/!\\ Code conflict. {key}")



with open("assets/airports.json", "w") as outfile:
    outfile.write(json.dumps(outdata))
