class Message {
  final int timestamp;

  final String pilotId; // sender
  final String text;
  final bool isEmergency;

  Message(this.timestamp, this.pilotId, this.text, this.isEmergency);
}
