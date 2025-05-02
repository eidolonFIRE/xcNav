import 'dart:math';

import 'package:flutter/material.dart';
import 'package:wheel_picker/wheel_picker.dart';

class WheelPickerTime extends StatefulWidget {
  const WheelPickerTime(
      {super.key,
      required this.initialTime,
      this.onTimeChanged,
      required this.textStyle,
      this.selectedIndexColor,
      required this.validRange});

  final DateTimeRange validRange;
  final DateTime initialTime;
  final TextStyle textStyle;
  final Color? selectedIndexColor;

  final Function(DateTime)? onTimeChanged;

  @override
  State<WheelPickerTime> createState() => _WheelPickerTimeState();
}

class _WheelPickerTimeState extends State<WheelPickerTime> {
  late final WheelPickerController _hoursWheel;
  late final WheelPickerController _minutesWheel;
  late final WheelPickerController _periodWheel;

  void _onTimeChanged() {
    final hour = _hoursWheel.selected + widget.validRange.start.hour;
    final minute = (_minutesWheel.selected + widget.validRange.start.minute) % 60;
    final time = DateTime(widget.initialTime.year, widget.initialTime.month, widget.initialTime.day, hour, minute);
    _periodWheel.shiftTo(time.hour >= 12 ? 1 : 0);
    debugPrint("Time: $time, ${time.hour}");
    widget.onTimeChanged?.call(time);
  }

  @override
  void initState() {
    _periodWheel = WheelPickerController(
      itemCount: 2,
      initialIndex: widget.initialTime.hour >= 12 ? 1 : 0,
    );

    _hoursWheel = WheelPickerController(
      itemCount: widget.validRange.end.hour - widget.validRange.start.hour + 1,
      initialIndex: widget.initialTime.difference(widget.validRange.start).inHours,
    );
    _minutesWheel = WheelPickerController(
      itemCount: (widget.validRange.duration.inSeconds / 60.0).ceil(),
      initialIndex: widget.initialTime.difference(widget.validRange.start).inMinutes,
    );

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final wheelStyle = WheelPickerStyle(
      itemExtent: widget.textStyle.fontSize! * widget.textStyle.height!, // Text height
      squeeze: 1.25,
      diameterRatio: .8,
      surroundingOpacity: .25,
      magnification: 1.2,
    );

    return Center(
      child: SizedBox(
        width: 200.0,
        height: 200.0,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _centerBar(context),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Row(
                children: [
                  Expanded(
                    child: WheelPicker(
                      builder: (context, index) => Text(
                        ((((index + widget.validRange.start.hour) - 1) % 12) + 1).toString(),
                        style: widget.textStyle,
                      ),
                      controller: _hoursWheel,
                      looping: false,
                      style: wheelStyle,
                      selectedIndexColor: widget.selectedIndexColor,
                      onIndexChanged: (index, interactionType) {
                        if (interactionType != WheelPickerInteractionType.control) {
                          _minutesWheel.setCurrent(max(0, index * 60 - widget.validRange.start.minute));
                          _onTimeChanged();
                        }
                      },
                    ),
                  ),
                  Text(":", style: widget.textStyle),
                  Expanded(
                    child: WheelPicker(
                      builder: (context, index) => Text(
                          "${(index + widget.validRange.start.minute) % 60}".padLeft(2, '0'),
                          style: widget.textStyle),
                      controller: _minutesWheel,
                      looping: false,
                      style: wheelStyle,
                      selectedIndexColor: widget.selectedIndexColor,
                      onIndexChanged: (index, interactionType) {
                        if (interactionType != WheelPickerInteractionType.control) {
                          _hoursWheel.setCurrent((index + widget.validRange.start.minute) ~/ 60);
                          _onTimeChanged();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  Expanded(
                    child: WheelPicker(
                      enableTap: false,
                      controller: _periodWheel,
                      onIndexChanged: (index, interactionType) => _onTimeChanged(),
                      builder: (context, index) {
                        return Text(["AM", "PM"][index], style: widget.textStyle);
                      },
                      looping: false,
                      style: wheelStyle.copyWith(
                        surroundingOpacity: 0,
                        shiftAnimationStyle: const WheelShiftAnimationStyle(
                          duration: Duration(seconds: 1),
                          curve: Curves.bounceOut,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hoursWheel.dispose();
    _minutesWheel.dispose();
    _periodWheel.dispose();
    super.dispose();
  }

  Widget _centerBar(BuildContext context) {
    return Center(
      child: Container(
        height: 38.0,
        decoration: BoxDecoration(
          color: const Color(0xFFC3C9FA).withAlpha(26),
          borderRadius: BorderRadius.circular(8.0),
        ),
      ),
    );
  }
}
