import argparse
import json
import numpy as np
import matplotlib.pyplot as plt
import datetime as dt

# Initialize parser
parser = argparse.ArgumentParser(description = "Post-process an xcNav log.")
parser.add_argument("file", type=argparse.FileType('r'))
parser.add_argument("-s", "--trim-start", type=int, default=0, nargs="?")
args = parser.parse_args()
infile = json.loads("".join(args.file.readlines()))


print(infile["xcNavVersion"])






class BleDeviceData:
    values: np.array

    def __init__(self, json, trim_start = 0):
        start_time = json["start_time"]
        self.values = np.array(json["data"][trim_start:]) + [start_time, 0]




#--- Fuel
logFuel = BleDeviceData(infile["ble_devices"]["xc170"]["deviceValues"]["fuel"], trim_start=args.trim_start)

# plot
fig, ax = plt.subplots()
x, y = zip(*logFuel.values)
x = [dt.datetime.fromtimestamp(each/1000) for each in x]

trendline = np.polyfit(x, y, 1)

p = np.poly1d(trendline)

ax.plot(x, y)
ax.plot(x, p(x), color="purple", linewidth=3, linestyle="--")

plt.show()