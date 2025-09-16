from __future__ import annotations

import argparse
import json
import numpy as np
from matplotlib.axes import Axes
import matplotlib.pyplot as plt
import datetime as dt
import bisect

# Initialize parser
parser = argparse.ArgumentParser(description = "Post-process an xcNav log.")
parser.add_argument("file", type=argparse.FileType('r'))
parser.add_argument("-s", "--trim-start", type=int, default=0, nargs="?")
parser.add_argument("-e", "--trim-end", type=int, default=0, nargs="?")
args = parser.parse_args()
inFile = json.loads("".join(args.file.readlines()))


print(inFile["xcNavVersion"])



def gaussian1D(data, kernel_size=5, sigma=1.0):
    def gkern(l=5, sig=1.):
        """Creates 1D gaussian kernel with length `l` and a sigma of `sig`"""
        ax = np.linspace(-(l - 1) / 2., (l - 1) / 2., l)
        gauss = np.exp(-0.5 * np.square(ax) / np.square(sig))
        return gauss / np.sum(gauss)

    return np.convolve(data, gkern(l=kernel_size, sig=sigma), mode='same')


class BleDeviceData:
    values: np.array

    def __init__(self, json, trim_start = 0, trim_end = 0):
        start_time = json["start_time"]
        numSamples = len(json["data"])
        self.values = np.array(json["data"][trim_start:(numSamples - trim_end)]) + [start_time, 0]

    
    def sample(self, time: int) -> float:
        """Sample data at timestamp (interpolated)"""
        index = bisect.bisect_left(self.values[:,0], time)
        index = max(1, min(len(self.values)-1, index))
        a = self.values[index-1]
        b = self.values[index]
        d = (time - a[0]) / (b[0] - a[0])
        return a[1] * (1.0 - d) + b[1] * d
    
    def mean(self):
        return np.mean(self.values[:,1])


#--- Logs
logFuel = BleDeviceData(inFile["ble_devices"]["xc170"]["datas"]["telemetry"]["fuel"], trim_start=args.trim_start, trim_end=args.trim_end)
logFanAmps = BleDeviceData(inFile["ble_devices"]["xc170"]["datas"]["telemetry"]["fanAmps"], trim_start=args.trim_start, trim_end=args.trim_end)
logCHT = BleDeviceData(inFile["ble_devices"]["xc170"]["datas"]["telemetry"]["cht"], trim_start=args.trim_start, trim_end=args.trim_end)
logEGT = BleDeviceData(inFile["ble_devices"]["xc170"]["datas"]["telemetry"]["egt"], trim_start=args.trim_start, trim_end=args.trim_end)
logRPM = BleDeviceData(inFile["ble_devices"]["xc170"]["datas"]["telemetry"]["rpm"], trim_start=args.trim_start, trim_end=args.trim_end)



def getRpmPerLift(rpm: BleDeviceData) -> tuple[list[float], list[float]]:
    vario = []
    samples = inFile["samples"]
    for i in range(len(samples)-1):
        if (samples[i]["time"] >= rpm.values[0][0] and samples[i]["time"] <= rpm.values[-1][0]):
            vario.append([(samples[i+1]["time"] + samples[i]["time"]) // 2, (samples[i+1]["alt"] - samples[i]["alt"]) / (samples[i+1]["time"] - samples[i]["time"]) * 1000])
    vario = np.array(vario)

    vario[:,1] = gaussian1D(vario[:,1], sigma=2)

    retX = []
    retY = []

    for each in vario:
        # loop up rpm
        retY.append(each[1])
        retX.append(rpm.sample(each[0]))
    return np.array(retX), np.array(retY)


#--- Plots

def plotFuel(ax: Axes, fuel: BleDeviceData):
    x, y = zip(*fuel.values)
    p = np.poly1d(np.polyfit(x, y, 1))
    ax.set_title(f"Fuel Trendline {p.coefficients[0] * 1000 * 3600:.2f} L/hr")
    trendline = p(x)
    x = [dt.datetime.fromtimestamp(each/1000) for each in x]
    ax.plot(x, y)
    ax.plot(x, trendline, color="purple", linewidth=2, linestyle="--")


def plotCooling(ax: Axes, fanAmps: BleDeviceData, cht: BleDeviceData):
    x, y = zip(*fanAmps.values)
    x2, y2 = zip(*cht.values)
    
    wh = 0.0
    for i in range(len(x)-1):
        t = float(x[i+1] - x[i]) / 1000.0 / 3600.0
        ma = (y[i+1] + y[i]) / 2
        wh += 12.0 * ma * t
    ax.set_title(f"Approx ~ Total: {wh:.1f}Wh, Average: {wh/float(x[-1]-x[0])*1000*3600:.1f}W")

    x = [dt.datetime.fromtimestamp(each/1000) for each in x]
    x2 = [dt.datetime.fromtimestamp(each/1000) for each in x2]

    ax.plot(x, y, label="Fan Amps", color="red")
    ax.legend(loc="upper left")
    ax.set_ylim(bottom=0, top=10)
    ax.set_ylabel("Fan Amps")
    ax2 = ax.twinx()
    ax2.plot(x2, y2, label="Engine CHT", color="green")
    ax2.set_ylim(bottom=170, top=260)
    ax2.set_ylabel("CHT Celsius")
    ax2.legend()

def plotCorrTempRpm(ax: Axes, rpm: BleDeviceData, egt: BleDeviceData, cht: BleDeviceData):
    x = rpm.values[:,1]
    y = cht.values[:,1]
    ax.set_title("Temperature at different RPM")
    ax.scatter(x, y, alpha=0.1, linewidths=0, color="blue", s=20, label="CHT")
    ax.set_ylim(bottom=190, top=250)
    ax.set_xlim(left=2700)
    ax.set_ylabel("CHT Celsius")
    ax.legend(loc="upper left")
    for lh in ax.legend_.legend_handles: 
        lh.set_alpha(1)
    ax.grid(visible=True, axis='x')

    ax2 = ax.twinx()
    x = rpm.values[:,1]
    y = egt.values[:,1]
    ax2.scatter(x, y, alpha=0.1, linewidths=0, color="green", s=20, label="EGT")
    ax2.set_ylim(bottom=400, top=700)
    ax2.set_xlim(left=2700, right=7000)
    ax2.set_ylabel("EGT Celsius")
    ax2.legend(loc="upper right")
    for lh in ax2.legend_.legend_handles: 
        lh.set_alpha(1)

def plotCorrRpmVario(ax: Axes, rpm: BleDeviceData):
    x, y = getRpmPerLift(rpm)
    order = np.argsort(x)
    p = np.poly1d(np.polyfit(x, y, 2))
    zeroCrossing = x[order][bisect.bisect_left(p(x[order]), 0)]
    ax.set_title(f"Vario x Engine RPM. Zero crossing: {zeroCrossing:.0f} rpm")
    ax.scatter(x, y, alpha=0.1, linewidths=0, color="purple", s=20)
    ax.plot(x[order], p(x[order]), color="black", linewidth=2, linestyle="--")
    ax.set_ylim(bottom=-4, top=5)
    ax.set_xlim(left=2700, right=7000)
    ax.set_ylabel("Vario (m/s)")
    ax.grid(visible=True)

def plotCorrRpmAmps(ax: Axes, rpm: BleDeviceData, amps: BleDeviceData):
    x = []
    y = []
    for t in amps.values[:,0]:
        x.append(rpm.sample(t))
        y.append(amps.sample(t))
    x = np.array(x)
    y = np.array(y)
    order = np.argsort(x)
    p = np.poly1d(np.polyfit(x, y, 10))
    ax.set_title(f"Fan Amps x Engine RPM")
    ax.scatter(x, y, alpha=0.1, linewidths=0, color="red", s=20)
    ax.plot(x[order], p(x[order]), color="black", linewidth=2, linestyle="--")
    # ax.set_ylim(bottom=0, top=10)
    ax.set_xlim(left=2700, right=7000)
    ax.set_ylabel("Amps")
    ax.grid(visible=True)

# def plotCorrTempPhase(ax: Axes, egt: BleDeviceData, cht: BleDeviceData):
#     x = []
#     y = []
#     for phase in range(-120, 121, 1):
#         integral = 0
#         for sweep in cht.values[120:-120,0]:
#             # sweep the whole timestamp range and add the abs difference
#             integral += abs(cht.sample(sweep) - (egt.sample(sweep - phase*1000)))
#         x.append(phase)
#         y.append(integral)
#     x = np.array(x)
#     y = np.array(y)
#     # normalize to phase=0
#     y = y - y[len(y)//2]

#     ax.set_title("Phase correlation between EGT / CHT  (+X is EGT first, +Y is more difference)")
#     ax.plot(x, y, color="green")
#     ax.grid(visible="both")

    
#--- Fill window with graphs
fig, axs = plt.subplots(5, figsize=(12, 20))
plotFuel(axs[0], logFuel)
plotCooling(axs[1], logFanAmps, logCHT)
plotCorrTempRpm(axs[2], logRPM, logEGT, logCHT)
plotCorrRpmVario(axs[3], logRPM)
plotCorrRpmAmps(axs[4], logRPM, logFanAmps)
# plotCorrTempPhase(axs[5], logEGT, logCHT)

plt.subplots_adjust(hspace=0.4)
plt.show()