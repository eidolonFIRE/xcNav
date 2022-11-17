# xcNav
This cross-platform app is unifying all the tools for coordinating a group, cross-country flight.
It is available on both Android and iOs.



---

## How you can contribute

[Patreon](https://www.patreon.com/xcnav)

Check the [wiki](https://github.com/eidolonFIRE/xcNav/wiki) for guiding developer principles.

[Getting started in Flutter](https://docs.flutter.dev/get-started/install)

PRs welcome!



------------------


This is a quick tour of xcNav version 2...




# Overview

##  Top Instruments
At the top is a basic set of intsruments.
- Ground speed on the left.
- Altitude on the right. Double tap to toggle which is primary.
- The wind indicator will show a wind sock when it has data. You can tap it to see more, but I will discuss that in a later chapter.

## Bottom Nav Bar
At the bottom is the navigation bar. There are four views as well as a slide-out menu.
Left-to-right:
1. Map
2. Side view
3. Waypoints
4. Group Chat

---
# Map View

## Focus Modes
The map can be made to follow you, or when you're flying with a group, it can keep everyone in frame.
The map can also rotate, or lock north-up. If the map map rotation is free, selecting one of the following modes will lock rotation to your heading.

## Measurement Tool
Tap anywhere to make measurements. You can move, add, or remove points. 
Each point shows the ground elevation and the cumulative distance down the path.
The X clears the measurement.

## Waypoints
Long-press to add a waypoint or path. If you select "path", add the points on the map before customizing the appearance of the waypoint.

You can tap a waypoint or path to navigate to it. If you select a path, it will show the ETA to intercept and complete the path. If you re-select the same path, it will flip directions.

---

# Side View
The side view shows your elevation over the ground. The white dashed line shows your prospective glide slope. You can use this slope indicator to time your arrival elevation to waypoints or make ensure you're climbing fast enough to make it over the next mountain.

The left half of the plot behind you shows your past elevation. The corrosponding left selector is how minutes to show from your log.

The right half of the plot shows future elevation. If you have no waypoint selected, it is tracing out a straight line in front of you by the number of miles selected. If you do have a waypoint selected, the plot is measuring altitude along the white line shown in the map view. This includes intercepting and following paths.


---


# Waypoints
The waypoints view shows a sorted list of all active waypoints and paths. By default they sort by distance away from you, but you can search by other traits: color, icon, and text. Select a waypoint to navigate to it.

Swiping left/right on a waypoint shows more options. 

## Library
The library holds collections of waypoints and paths. You can use one or more items from a collection, or push individual items back into a collection.

## Adding to a collection
To add to or modify a collection in your library, you select edit and make your modifications. 
From the waypoints view, you can also push a waypoint into a collection by sliding left and selecting "add to".

---
# Group
xcNav is most useful when flying in a group with other pilots.
You get:
- Live location of other pilots.
- You can see what waypoint they have selected and what their eta is.
- And, when you're closing a gap, you can see your time to intercept.
- Also, Loaded waypoints are all syncronized between everyone.
- Lastly, you can text message the group without leaving the app. 

Tap the lightning bolt to quickly send a pre-prepared message.

## Joining up with others
To join up with other pilots and see who is in your group, tap the group button in the top right of the chat view.
To link up, you can either scan another pilot's code, or have them scan yours. If you aren't able to scan a code, you can also optionally type the group code into the top of the screen.

If you scan their code, you are joining their group; if they scan yours, they join your group. Everyone in a given group will have the same code, so you can join on any member of a group, not just the pilot who started the group.
The group will remain active for a few days, but it's not encouraged to remain in a group unless you are actively flying together.
You can leave the group or join a past group from the "group members" screen.


---
# Wind Detector
The wind detector is always running, but it's only using data from the last several minutes and it works best if you have flown in different directions. To get a good reading, you need to turn at least 90degrees. I recommend doing some gentle S-turns while on cross-country. Although it's not usually necessary, to get the most accurate reading turn a full circle. This works best for very precise measurements in weak wind or before landing.

You'll know you have a good reading when the aircraft speed looks correct. If it's way off, you need better data. If you want to make a clean measurement, tap the reset button top-right of the diagram, then slowly S-turn back and forth or fly in a circle.

The wind sock shown on the home screen can be made to either track North-up, or as relative to your heading.

The fancy diagram shows how fast you flew in each direction. The wind speed is solved by fitting a circle over those samples. The faster the wind, the more offset the circle will be. The faster you fly, the larger the circle will be.

---
# Misc

## ADSB
It's highly recommended you fly with ADSB-in enabled. You get audio proximity warnings and can see other aircraft in the map view.
You'll need some external hardware and can see more info on that if you flip ADSB on and tap the "?" for info.

## Audio Cues
To get spoken audio updates for various things, dial up the "audio cues" from the slide-out menu. Tap the gear to toggle the different catagories.
Chat text-to-speech is controlled independently in the chat view.

## Simulator
You can try out the app from the ground by turning on the location spoofer. Go to the settings and scroll down to the debug section.
If you have a waypoint selected when you enable the spoofer, you will be teleported to the waypoint before the spoofer starts.

# Conclusion
Checkout the "about" screen to follow links to the various resources... Patreon, Github, or the discord.
That's it; Fly safe!
